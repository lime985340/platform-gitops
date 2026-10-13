# Secret Manager access budget for GitHub Actions

The GitOps workflow must reserve its maximum planned Secret Manager access calls
before authenticating to Google Cloud or reading any secret payload.

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
- At 9,900 reserved calls, the action emits a warning. Later runs are blocked if
  their reservation would exceed 9,900. A run is rejected before any secret read
  if the projected count exceeds the cap.
- Selective runs should reserve their own maximum (`1` for one Q Interior bundle,
  for example). Any retries that can repeat a Secret Manager access must be
  included in the reservation or avoided.

This design allows at most `floor(9,900 / 6) = 1,650` full-scope runs in a month,
assuming each run reads each bundle once. If 58 values were instead stored and
read as 58 separate secret payloads, a run would use 58 calls and the same guard
would allow at most `floor(9,900 / 58) = 170` such runs. The approved bundle plan
uses six calls, not 58.

## Workflow integration

The GitHub Actions job that reads secrets must:

1. Set a repository-wide concurrency group with `cancel-in-progress: false` so
   two reservations cannot race.
2. Grant `contents: write` to `GITHUB_TOKEN`; the token writes a count-only ledger
   to the `secret-manager-access-budget` branch.
3. Check out the repository, then invoke
   `.github/actions/reserve-secret-manager-access` **before** Google OIDC
   authentication and before every `gcloud secrets versions access` call.
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
      - uses: ./.github/actions/reserve-secret-manager-access
        with:
          reserve: "6"
      # Google Workload Identity authentication and secret reads follow here.
```

The state branch contains only the month and reserved-call count, never secret
payloads. Failed runs after reservation remain counted, intentionally favoring
an early stop over undercounting. A deleted or manually reset state branch would
reset this repository's ledger, so the branch must be protected from deletion
and manual edits.

## GitHub Actions reseal workflow

The draft GitHub migration adds `.github/workflows/reseal-secrets.yml`. It is a
manual workflow, rejects runs against the default branch, serializes secret
reseals, and reserves access calls before OIDC authentication. A full run
reserves six calls; a Q Interior dev or prod run reserves one.

The workflow expects six Secret Manager payloads. Each payload is a gzip tar
archive containing regular files at its archive root, named exactly as follows:

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
`GCP_PROJECT_ID`, `GCP_WIF_PROVIDER`, `GCP_SERVICE_ACCOUNT`, and the public
`SEALED_SECRETS_CERT` value. Configure these **repository secrets**:
`GITLAB_REGISTRY_USERNAME`, `GITLAB_REGISTRY_TOKEN`, and
`GRAPHDB_LICENSE_BASE64` (the GraphDB license file encoded as Base64; required
only for `all`). Grant the trusted Workload Identity service account Secret
Manager access only to the six named secrets. The workflow keeps the current
GitLab image registry credentials for sealing Kubernetes pull secrets.

The workflow writes the generated SealedSecrets to the selected non-default
GitHub branch and does not merge them. Review and merge those generated files
through a pull request. This migration PR does not configure Google Cloud IAM or
copy any secret payload.

## Limits

This ledger measures reservations made by this GitHub repository. Google
aggregates the free allowance across every project linked to the billing
account, so the ledger cannot see reads from other projects or principals. The
100-call gap below the published 10,000-call free allowance is a buffer, not a
hard account-wide cap. Do not grant other workloads access to these secrets if
the intent is to keep their reads inside this CI ledger.

The helper, composite action, and manual reseal workflow are in the GitHub
migration draft PR. They are not active until that PR is merged and the GCP
Workload Identity, billing, Secret Manager bundles, repository variables, and
repository secrets are configured.
