# GitHub Actions and GHCR deployment cutover

The service repositories publish images to private GitHub Container Registry packages as `ghcr.io/lime985340/<repository>:<commit-sha>` from `main` and as both commit-SHA and `vMAJOR.MINOR.PATCH` tags from a release tag. A `main` build updates the dev GitOps overlay. A release-tag push publishes the version image; a maintainer then runs that service repository workflow manually with `release_tag: vX.Y.Z` to create a production GitOps PR. Merging that PR starts production deployment. Both paths remain gated until the GHCR cutover is ready.

## Required settings in each service repository

Add the repository secret `PLATFORM_GITOPS_TOKEN`. Use a fine-grained personal access token whose only repository access is `lime985340/platform-gitops`, with `Contents: read/write` and `Pull requests: read/write`. For `main` builds it updates the matching `dev` Kustomize file on GitOps `main`. Production image publication and production deployment are separate: push a `vMAJOR.MINOR.PATCH` tag to publish it, then run the workflow manually with that tag to create a GitOps production PR. Production starts only after a person reviews and merges the PR. The token therefore needs `Contents: read/write` and `Pull requests: read/write` on `lime985340/platform-gitops`.

Set the repository variable `GHCR_DEPLOY_DEV_ENABLED` to the string `true` only after the GitOps dev overlay uses GHCR and the dev pull secret has been sealed. Set `GHCR_DEPLOY_PROD_ENABLED` to `true` only after production images and pull credentials have also been migrated. If these variables are unset or not `true`, image publishing can proceed but GitOps updates stay disabled.

## Required settings in `platform-gitops`

Add repository secrets `GHCR_READ_USERNAME` and `GHCR_READ_TOKEN`. The token must be a classic personal access token with only `read:packages`, and its owner must have access to the private packages. The existing `SEALED_SECRETS_CERT` secret is also required.

Run **Reseal workload secrets** on a non-main review branch with `ghcr-dev` to create pull credentials for dev namespaces, or `ghcr-all` for dev and prod. This workflow reads no Secret Manager values. Review and merge its SealedSecret changes before switching any workload to GHCR.

When resealing `q-interior-dev`, `q-interior-prod`, or `all`, the workflow also derives the matching Neon hostname from the corresponding `Q_INTERIOR_API_*_ENV` Secret Manager file and updates that environment's Cilium DB-egress policy. If GHCR SealedSecrets already exist, the GHCR credentials must be present so resealing preserves the pull credentials.

The published GHCR packages are private by default. The GitOps manifests use `ghcr.io/lime985340/*` and `ghcr-regcred`. Do not enable either deployment variable until the matching namespaces contain the generated `ghcr-regcred` Secret, Argo CD can read the private GitHub GitOps repository, and the GitOps source is switched to GitHub.
