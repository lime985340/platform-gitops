# GitOps

This repository contains the Kubernetes manifests managed by Argo CD.
Secret values are provided through GitLab CI/CD Variables. Plaintext values are
never committed to Git; only encrypted `SealedSecret` data is stored.

Cluster and Argo CD installation prerequisites are documented in
[`docs/cluster-bootstrap.md`](docs/cluster-bootstrap.md).
Sealed Secrets recovery is documented in
[`docs/sealed-secrets-recovery.md`](docs/sealed-secrets-recovery.md), and
service CI image tag updates are described in
[`docs/image-updates.md`](docs/image-updates.md).

## Secret management

각 GitLab CI/CD Variable에 어떤 형식의 값을 입력하는지는
[Secret Variables 입력 가이드](docs/secret-variables.md)를 참고합니다.

### Sealed Secrets 흐름

```text
GitLab CI Variables
  → kubeseal
  → encrypted SealedSecret YAML
  → Git commit/push
  → Argo CD
  → Sealed Secrets Controller
  → Kubernetes Secret
```

수동 작업 `seal:workload-secrets`가 공개 인증서로 Secret을 암호화하고,
암호화된 YAML을 현재 브랜치에 `[skip ci]` 커밋으로 Push합니다. CI는
Kubernetes API에 접근하지 않으므로 `KUBECONFIG`가 필요하지 않습니다.

각 변수의 입력 형식은 [Secret Variables 입력 가이드](docs/secret-variables.md)를
참고합니다. 주요 변수는 다음과 같습니다.

- `SEALED_SECRETS_CERT`: Controller 공개 인증서, `File` 타입
- `GITOPS_PUSH_TOKEN`: 암호화 YAML Push 권한이 있는 토큰
- `ATMO_API_DEV_*`, `ATMO_API_PROD_*`: API 환경별 File 변수
- `GITLAB_REGISTRY_DOCKER_CONFIG`: Registry 인증 설정 File 변수

Kubernetes Secret 이름은 기존과 동일합니다. API는 DB, JWT, OAuth,
Publicdata Secret을 사용하고 API/Web의 private 이미지 Pull에는
`gitlab-regcred`를 사용합니다.

GitLab.com shared runner로 충분하므로 현재 저장소에는 GitLab Runner Helm
Chart와 Runner ServiceAccount를 추가하지 않습니다. Sealed Secrets
Controller 설치는 `argocd/applications/sealed-secrets.yaml`의 Helm
Application이 담당합니다.

## Argo CD recursion and Kustomize

The bootstrap Application in `bootstrap/argocd-root.yaml` uses:

```yaml
source:
  path: argocd
  directory:
    recurse: true
```

This recursively discovers the Application, AppProject, and ApplicationSet
YAML files under `argocd/`. It does not recursively render all directories
under `platform/`.

The `platform` ApplicationSet generates the two Git-backed platform
Applications (`policies` and `cloudflare-quick-tunnel`) from
one template. The Git revision is declared once in that template. The
`workloads` ApplicationSet generates the environment Applications from the
workload directory layout. Helm-based platform components remain individual
Applications because their `targetRevision` values are Helm Chart versions,
not Git branches.

Argo CD Application names use short component names such as `redis`, `grafana`,
and `traefik`. The `platform` AppProject and the source directories already
provide the grouping context, so `platform-` and `cluster-` prefixes are not
needed. This naming rule applies only to Argo CD Application objects; existing
Helm release names, Kubernetes Service names, and internal DNS addresses are
unchanged.

All platform and workload namespaces are created by Argo CD with
`CreateNamespace=true`. Namespace YAML files are not stored in the repository.
The target namespace is declared in each Application's
`destination.namespace`; the workload ApplicationSet derives its namespace
from the workload path.

The simplified sync-wave order is:

| Wave | Resources |
| --- | --- |
| `-20` | AppProjects |
| `-10` | Cilium policies |
| `0` | Traefik, Redis, Loki, Prometheus |
| `1` | Promtail, Grafana |
| `2` | Workload ApplicationSet |
| `3` | Cloudflare Quick Tunnel |

The workload layout keeps six Kustomizations under `workloads/atmo/`: one
resource composition file for API, one for Web, and one dev/prod environment
file for each service. The shared patches are applied once in the service
resource composition, while each environment only sets its namespace and image
tag. This removes the redundant `common` layer without using unsafe
cross-directory Kustomize loading. External routing is currently handled by the
hostless Quick Tunnel Ingress resources in the Atmo prod workload
Kustomizations. The dev Services remain available for cluster-internal access
or port-forwarding without an Ingress.

The Cloudflare Quick Tunnel uses a raw Directory source. Redis uses the
Bitnami Redis Helm Chart directly from the Docker Hub OCI registry.

### Helm charts and raw platform manifests

Platform components use one of two deployment styles:

- Sealed Secrets, Traefik, Grafana, Loki, Prometheus, and Promtail use external
  Helm Charts.
  Their Argo CD Application files define the chart repository, chart version,
  and Helm values. The chart renders the underlying Deployments, Services, and
  configuration resources.
- Cloudflare Quick Tunnel uses raw Kubernetes YAML under `platform/`. The
  `platform` ApplicationSet generates its Argo CD Application, while
  `deployment.yaml` defines the resource and pinned container image.
- Redis uses the Bitnami Redis Helm Chart. Its Argo CD Application defines the
  OCI chart repository, chart version, standalone mode, disabled persistence,
  and resource limits. The chart generates the Redis Deployment and Service.

The Sealed Secrets Controller uses the Bitnami OCI Helm Chart in the
`sealed-secrets` namespace. The controller stores its decryption Private Key
in the cluster. GitLab CI only runs `kubeseal` with the public certificate and
Pushes encrypted `SealedSecret` YAML to Git; it does not need Kubernetes API
access. The `kubeseal` CLI is downloaded in the CI job and is not a Helm Chart
resource.

The current Cloudflare integration intentionally keeps a small raw Deployment.
It runs the Quick Tunnel command
`cloudflared tunnel --url http://traefik.traefik.svc.cluster.local:80`, which
does not require a Cloudflare account, tunnel token, credentials JSON, or
configuration file. This is the simplest option for the current test setup and
routes the temporary public address to the Atmo prod Services. The generated
`trycloudflare.com` address is expected to change when the pod is recreated.

For a future fixed hostname or production-style setup, migrate this Application
to the [`community-charts/cloudflared` Helm Chart](https://artifacthub.io/packages/helm/community-charts/cloudflared).
That Chart is intended for a Named or locally-managed Tunnel: it requires a
tunnel name, `cert.pem`, and a credentials JSON file, and generates the
`cloudflared` configuration and Deployment from Helm values. The future Argo CD
Application would use the Chart repository directly, for example:

```yaml
source:
  repoURL: https://community-charts.github.io/helm-charts
  chart: cloudflared
  targetRevision: 2.2.11
```

Before that migration, add the Chart repository to the `platform` AppProject's
`sourceRepos` and create the required Cloudflare credential Secrets in the
`cloudflared` namespace through the protected Secret management process. Do not
place `cert.pem`, credentials JSON, tunnel tokens, or base64-encoded Secret
values in Git. See the [Cloudflare Kubernetes guide](https://developers.cloudflare.com/tunnel/deployment-guides/kubernetes/)
for the Named Tunnel deployment model.

Named Tunnel 전환 후에는 Quick Tunnel의 랜덤 주소 대신 직접 관리하는 도메인과
서브도메인을 사용한다. 도메인 하나만 있으면 여러 서브도메인을 만들 수 있다.
예를 들어 `example.com` 하나로 다음과 같이 환경을 분리할 수 있다.

```text
atmo-dev.example.com → atmo-web-dev
api-dev.example.com  → atmo-api-dev

atmo.example.com     → atmo-web-prod
api.example.com      → atmo-api-prod
```

현재 저장소는 `prod`만 외부에 공개하고 `dev`는 클러스터 내부 확인용으로
사용한다. 따라서 현재 Quick Tunnel은 `prod` 환경의 hostless Ingress에
`/`와 `/api` 경로를 연결하며, `dev`에는 Ingress를 배포하지 않는다.
향후 개발 환경도 외부에 공개할 때만 `dev` 환경에 별도 Ingress를 추가하고,
`atmo-dev.example.com` 같은 서브도메인을 지정한다. 운영용 Named Tunnel을
사용할 때는 `atmo.example.com`과 `api.example.com` 같은 운영 서브도메인을
`prod` Ingress에 지정한다.

요청 흐름은 다음과 같다.

```text
Named Tunnel → cloudflared → Traefik → Kubernetes Ingress → Service
```

Cloudflared가 Traefik을 통하지 않고 Service로 직접 연결되도록 구성하면
Ingress를 생략할 수도 있지만, 현재 저장소의 라우팅 구조를 유지하려면
Named Tunnel과 외부에 공개할 환경의 hostname 기반 Ingress를 함께 사용한다. Cloudflare가
외부 TLS를 처리하므로 Tunnel과 Traefik 사이에는 내부 HTTP를 사용할 수 있으며,
이 경우 Kubernetes `Ingress`에 별도 TLS Secret이나 cert-manager를 반드시
추가할 필요는 없다.

Redis currently uses the Bitnami Helm Chart in standalone mode with one
Deployment replica, no PVC, no authentication, and no AOF/RDB persistence.
The chart's master Service is `redis-master`, so the Atmo API Secret values
must use `redis-master.redis.svc.cluster.local` as `SPRING_REDIS_HOST`.
This Redis instance is ephemeral and must not be treated as a production data
store. Enable authentication and persistence, or use a managed Redis service,
before production use. The chart supports these settings through its Helm
values. See the [Bitnami Redis Chart](https://artifacthub.io/packages/helm/bitnami/redis)
for the available configuration. Because the chart is sourced from a Docker
Hub OCI registry, Argo CD installations that do not auto-discover public OCI
sources must register `registry-1.docker.io/bitnamicharts` as a Helm OCI
repository with `enableOCI: true` outside this repository.

The only raw `Deployment` resource under `platform/` is currently
`cloudflared`. The Atmo API and Web Deployments are workload resources, while
Cilium policies and Ingresses are raw Kubernetes resources by nature and do
not need Helm Charts.

The bootstrap Application's recursion setting applies only to its `argocd/`
source. Platform raw resources are kept directly under their Application
source directories.

If the cluster is recreated, restore the Sealed Secrets Controller Private Key
backup before syncing workload SealedSecrets. Argo CD manages both the
workload manifests and encrypted SealedSecret resources; the Controller
creates the Kubernetes Secret objects.

## Validation

The `validate:manifests` job renders the remaining Kustomize directories under
`workloads/` and validates the raw YAML resources under `platform/`. The
validation does not require Secret values.

## Argo CD revision policy

This feature branch intentionally keeps
`refs/heads/feature/clean-gitops-layout` in the bootstrap and ApplicationSet
sources so the branch can be tested before merging. The bootstrap source is the
one-time entry point; the `platform` ApplicationSet owns the revision for its
Git-backed platform Applications, and the `workloads` ApplicationSet owns the
revision used for generated workload Applications. Change these revisions to
`refs/heads/main` only as part of the merge or the first post-merge cleanup.

Do not enable shell tracing for the secret job and never commit `.env` files,
plain Secret YAML, passwords, tokens, Controller Private Keys, or kubeconfig
files. Encrypted `SealedSecret` YAML is expected to be committed.
