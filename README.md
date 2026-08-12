# GitOps

This repository contains the Kubernetes manifests managed by Argo CD.
Secret values are managed in the GitLab CI/CD Variables of this GitOps
project. No plaintext or encrypted secret values are committed to Git.

## Secret management

The repository provides one manual job in `.gitlab-ci.yml`:

- `sync:workload-secrets`: creates the Atmo API and registry Secrets in the
  development and production namespaces.

The jobs run `ci/sync-secrets.sh`. The script sends generated Secret
manifests directly to Kubernetes and removes its temporary files when it
finishes. Secret values are never printed by the script.

### Required GitLab Variables

Create these variables in the GitOps project's `Settings > CI/CD > Variables`.
Use `Protected` for production values and restrict who can run the secret
jobs. Use `File` type for variables whose value contains multiple lines.

Cluster access:

- `KUBECONFIG` as a protected `File` variable. The CI jobs in this repository
  are designed for a GitLab.com shared runner and do not use GitLab Agent.

Workload values, all as `File` variables containing `KEY=value` lines:

- `ATMO_API_DEV_DB_ENV`
- `ATMO_API_DEV_JWT_ENV`
- `ATMO_API_DEV_OAUTH_ENV`
- `ATMO_API_DEV_PUBLICDATA_ENV`
- `ATMO_API_PROD_DB_ENV`
- `ATMO_API_PROD_JWT_ENV`
- `ATMO_API_PROD_OAUTH_ENV`
- `ATMO_API_PROD_PUBLICDATA_ENV`
- `GITLAB_REGISTRY_DOCKER_CONFIG`, containing the Docker registry JSON

Example `ATMO_API_DEV_DB_ENV` value:

```env
SPRING_DATASOURCE_URL=jdbc:postgresql://db.example.com:5432/atmo
SPRING_DATASOURCE_USERNAME=atmo
SPRING_DATASOURCE_PASSWORD=REPLACE_WITH_REAL_VALUE
SPRING_REDIS_HOST=redis.example.com
SPRING_REDIS_PORT=6379
```

The OAuth file must contain the keys used by the Atmo API for Kakao, Google,
and Naver. The registry file must contain the Docker `config.json` content.

### Run the secret sync

After adding or changing a variable, open `Build > Pipelines` and run the
pipeline. Start `sync:workload-secrets` after the application variables are
ready. Secret synchronization failures now fail the manual job and must be
resolved before considering the pipeline successful.

No Git commit is required for a Secret value change. The generated Kubernetes
Secret names remain stable:

- `atmo-api-dev/atmo-db-secret`, `atmo-jwt-secret`, `atmo-oauth-secret`, and
  `atmo-publicdata-secret`
- The same four API Secrets in `atmo-api-prod`
- `gitlab-regcred` in both Atmo API namespaces and both Atmo Web namespaces

The application manifests reference these names, while the Secret objects are
created by the CI job. If a workload reads a changed value only at startup,
restart that workload after the sync job completes.

### Cluster access from GitLab CI

The shared runner must be able to reach the Kubernetes API through the
network. A protected `KUBECONFIG` File variable is not enough when the API
endpoint is private or only available on the developer's PC.

The current local `kind` cluster cannot be reached by a GitLab.com shared
runner. The secret jobs will work only after the cluster has a reachable API
endpoint and the API server firewall allows the runner traffic. Exposing the
Kubernetes API publicly and granting a broad cluster-admin kubeconfig is not
recommended; use a narrowly scoped service account and protect the variable.

If the target remains a local `kind` cluster, run the same
`ci/sync-secrets.sh` script locally with the GitLab variable values supplied
through a secure local environment instead of running the CI job.

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

Each child Application chooses its own source path. Static platform resources
are loaded directly by Argo CD's Directory source. The `cluster-policies`
Application loads the raw Cilium policy YAML files directly from
`platform/policies`.

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

- Traefik, Grafana, Loki, Prometheus, and Promtail use external Helm Charts.
  Their Argo CD Application files define the chart repository, chart version,
  and Helm values. The chart renders the underlying Deployments, Services, and
  configuration resources.
- Cloudflare Quick Tunnel uses raw Kubernetes YAML under `platform/`. Its Argo
  CD Application points to the Git directory, and `deployment.yaml` defines
  the resource and pinned container image.
- Redis uses the Bitnami Redis Helm Chart. Its Argo CD Application defines the
  OCI chart repository, chart version, standalone mode, disabled persistence,
  and resource limits. The chart generates the Redis Deployment and Service.

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

If the cluster is recreated, run the secret jobs again. Argo CD manages the
workload manifests; the GitLab CI secret job manages these Kubernetes Secret
objects.

## Validation

The `validate:manifests` job renders the remaining Kustomize directories under
`workloads/` and validates the raw YAML resources under `platform/`. The
validation does not require Secret values.

## Argo CD revision policy

This feature branch intentionally keeps `feature/clean-gitops-layout` in the
bootstrap, Application, and ApplicationSet sources so the branch can be tested
before merging. Change these revisions to `main` only as part of the merge or
the first post-merge cleanup.

Do not enable shell tracing for the secret jobs and never commit `.env` files,
plain Secret YAML, passwords, tokens, or kubeconfig files.
