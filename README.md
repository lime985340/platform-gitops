# GitOps

This repository contains the Kubernetes manifests managed by Argo CD.
Secret values are managed in the GitLab CI/CD Variables of this GitOps
project. No plaintext or encrypted secret values are committed to Git.

## Secret management

The repository provides two manual jobs in `.gitlab-ci.yml`:

- `sync:platform-secrets`: creates the Argo CD GHCR credentials.
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

Platform values:

- `PLATFORM_GHCR_USERNAME`
- `PLATFORM_GHCR_TOKEN`

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
pipeline. Start the appropriate manual job:

1. Run `sync:platform-secrets` after Argo CD is installed.
2. Run `sync:workload-secrets` after the application variables are ready.

No Git commit is required for a Secret value change. The generated Kubernetes
Secret names remain stable:

- `argocd/ghcr-repo-creds`
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
Application uses its own `directory.recurse: true` setting to load the raw
Cilium policy YAML files below `platform/policies`.

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

The remaining Kustomizations are under `workloads/`. They are intentional:
the base and common layers compose resources and patches, while each dev/prod
environment sets its namespace and image tag. External routing is handled by
the hostless Quick Tunnel Ingress resources under `platform/networking`.

The Cloudflare Quick Tunnel directory also uses a raw Directory source with
`directory.recurse: true` because it contains multiple YAML files below its
resource path.

The bootstrap Application's recursion setting applies only to its `argocd/`
source. The `cluster-policies` Application has a separate recursion setting
for the raw policy files under `platform/policies`.

If the cluster is recreated, run the secret jobs again. Argo CD manages the
workload manifests; the GitLab CI secret job manages these Kubernetes Secret
objects.

## Validation

The `validate:kustomize` job renders the remaining Kustomize directories under
`workloads/`. Static platform resources are validated as plain YAML resources.
The validation does not require Secret values.

Do not enable shell tracing for the secret jobs and never commit `.env` files,
plain Secret YAML, passwords, tokens, or kubeconfig files.
