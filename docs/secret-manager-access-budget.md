# Secret Manager access budget for GitHub Actions

The GitOps workflow authenticates to Google Cloud, reads the billing account's
current project list and Secret Manager access request metrics, then reserves
the run's maximum planned calls before reading any secret payload.

## Budget policy

- Monthly GitOps CI guard: **9,900 access operations**.
- Maximum full-scope run in the planned bundle design: **6 access operations**,
  one for each of the six bundled payloads.
- The 13 runtime environment files are grouped into six Secret Manager payloads.
  Keys inside a payload do not make additional `access` API calls.
- The migration inventory currently records 25 project-level and 3 inherited
  group-level GitLab variable entries. It did not read the contents of the 13
  File variables, so a separate count of environment keys such as 58 is not
  verified by that inventory.
- The preflight queries Cloud Monitoring's
  `serviceruntime.googleapis.com/api/request_count` for Secret Manager API
  requests in each project currently associated with the configured billing
  account. It deliberately counts all Secret Manager API methods, including
  free management calls, so the estimate errs high. It adds this run's
  reservation and CI reservations from the last 30 minutes, then blocks before
  any secret read if the projection exceeds 9,900.
- If the billing project list or any project's metrics cannot be read, the
  workflow fails closed before Secret Manager access.
- Selective runs should reserve their own maximum (`1` for one Atmo or Q Interior
  environment bundle, for example). Any retries that can repeat a Secret Manager
  access must be included in the reservation or avoided.

This design allows at most `floor(9,900 / 6) = 1,650` full-scope runs in a month,
assuming each run reads each bundle once. If 58 values were instead stored and
read as 58 separate secret payloads, a run would use 58 calls and the same guard
would allow at most `floor(9,900 / 58) = 170` such runs. The approved bundle plan
uses six calls, not 58.

## Workflow integration

The GitHub Actions job that reads secrets must:

1. Set a repository-wide concurrency group with `cancel-in-progress: false` so
   two reservations cannot race.
2. Grant `contents: write` to `GITHUB_TOKEN`; the token writes a count-and-time
   reservation ledger to the `secret-manager-access-budget` branch.
3. Authenticate through Google OIDC, then invoke
   `.github/actions/reserve-secret-manager-access` before every
   `gcloud secrets versions access` call.
4. Use `reserve: "6"` for the full-scope job. Set a smaller reservation only
   when the job is guaranteed to read fewer bundles.

Example placement:

```yaml
concurrency:
  group: gitops-secret-manager-access
  cancel-in-progress: false

jobs:
  seal-secrets:
    permissions:
      contents: write
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: google-github-actions/auth@v3
        with:
          project_id: ${{ vars.GCP_PROJECT_ID }}
          workload_identity_provider: ${{ vars.GCP_WIF_PROVIDER }}
          service_account: ${{ vars.GCP_SERVICE_ACCOUNT }}
      - uses: google-github-actions/setup-gcloud@v3
      - uses: ./.github/actions/reserve-secret-manager-access
        with:
          reserve: "6"
      # Secret Manager payload reads follow only after the preflight passes.
```

The state branch contains only the month, request counts, and reservation
timestamps, never secret payloads. Failed runs after reservation remain counted
for 30 minutes to cover metric publication delay, intentionally favoring an
early stop over undercounting. A deleted or manually reset state branch removes
that short-lived buffer.

## GitHub Actions reseal workflow

The draft GitHub migration adds `.github/workflows/reseal-secrets.yml`. It is a
manual workflow, rejects runs against the default branch, serializes secret
reseals, and checks usage after OIDC authentication but before reading secret
payloads. A full run reserves six calls; an Atmo or Q Interior dev/prod run
reserves one.

The workflow expects six Secret Manager payloads. Each payload is a gzip tar
archive containing regular files at its archive root, named exactly as follows.
The Secret Manager console can store a text-only version as
`GITOPS_TAR_GZ_BASE64_V1` followed by a newline and the archive's Base64 text;
the workflow decodes this wrapper before extraction. Raw gzip versions remain
supported.

| Secret Manager secret | Required archive files |
| --- | --- |
| `atmo-api-dev` | `ATMO_API_DEV_DB_ENV`, `ATMO_API_DEV_JWT_ENV`, `ATMO_API_DEV_OAUTH_ENV`, `ATMO_API_DEV_PUBLICDATA_ENV` |
| `atmo-api-prod` | `ATMO_API_PROD_DB_ENV`, `ATMO_API_PROD_JWT_ENV`, `ATMO_API_PROD_OAUTH_ENV`, `ATMO_API_PROD_PUBLICDATA_ENV` |
| `neople-api-dev` | `NEOPLE_GAME_ANALYTICS_API_DEV_ENV`; optional `NEOPLE_GAME_ANALYTICS_API_DEV_DB_ENV` |
| `neople-api-prod` | `NEOPLE_GAME_ANALYTICS_API_PROD_ENV`, `NEOPLE_GAME_ANALYTICS_API_PROD_DB_ENV` |
| `q-interior-api-dev` | `Q_INTERIOR_API_DEV_ENV` |
| `q-interior-api-prod` | `Q_INTERIOR_API_PROD_ENV` |

Archive extraction accepts only unique regular files with simple root-level
names. The workflow does not print bundle contents. It keeps temporary bundle
files under the ephemeral runner's temp directory and removes them at job end.

Before running it, configure these **repository variables** in `platform-gitops`:
`GCP_PROJECT_ID`, `GCP_BILLING_ACCOUNT_ID`, `GCP_WIF_PROVIDER`,
and `GCP_SERVICE_ACCOUNT`. Configure these **repository secrets**:
`SEALED_SECRETS_CERT`,
`GITLAB_REGISTRY_USERNAME`, `GITLAB_REGISTRY_TOKEN`, and
`GRAPHDB_LICENSE_BASE64` (the GraphDB license file encoded as Base64; required
only for `all`). Grant the trusted Workload Identity service account Secret
Manager access only to the six named secrets. The workflow keeps the current
GitLab image registry credentials for sealing Kubernetes pull secrets. Atmo
selective runs also reseal the GHCR pull credential for only the selected Atmo
API environment.

The workflow writes the generated SealedSecrets to the selected non-default
GitHub branch and does not merge them. Review and merge those generated files
through a pull request. This migration PR does not configure Google Cloud IAM or
copy any secret payload.

## Limits and required Google Cloud access

The Google Cloud Free Tier aggregates Secret Manager operations across
projects linked to a billing account. Cloud Billing's project-list API provides
the projects currently linked to that account; Cloud Monitoring then provides
project-level request metrics. Grant the GitHub workload identity:

- `roles/billing.viewer` on the billing account, which includes
  `billing.resourceAssociations.list`.
- `roles/monitoring.viewer` on every project returned for the billing account.
- The `cloudbilling.googleapis.com` and `monitoring.googleapis.com` APIs must be
  enabled in `GCP_PROJECT_ID`.

The `serviceruntime.googleapis.com/api/request_count` metric is sampled every
60 seconds and can take up to 1,800 seconds to appear. The workflow counts all
Secret Manager API methods, including non-billable management calls, and adds
its own reservations from the last 30 minutes. It cannot account for other
callers that have not appeared in Monitoring yet. The metric-based check is therefore
a conservative CI preflight, not Google's authoritative billing meter or a
hard billing-account cap. Other projects or principals can still use the shared
free allowance. The 100-call gap below 10,000 is a safety buffer, not a
guarantee against delayed or external usage. Billing export data is not used as
the gate because it can also lag actual use.

The guard cannot pass until the billing account ID, Workload Identity, IAM
access, APIs, Secret Manager bundles, repository variables, and repository
secrets are configured.
