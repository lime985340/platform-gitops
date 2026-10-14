# GitHub Actions and GHCR deployment cutover

The service repositories publish images to private GitHub Container Registry packages as `ghcr.io/lime985340/<repository>:<commit-sha>` on `main` and as both commit-SHA and `vMAJOR.MINOR.PATCH` tags for release tags. GitOps image-tag updates are gated until the GHCR cutover is ready.

## Required settings in each service repository

Add the repository secret `PLATFORM_GITOPS_TOKEN`. Use a fine-grained personal access token whose only repository access is `lime985340/platform-gitops`, with `Contents: read and write`. The workflow uses it only to update the matching environment Kustomize file on GitOps `main`.

Set the repository variable `GHCR_DEPLOY_DEV_ENABLED` to the string `true` only after the GitOps dev overlay uses GHCR and the dev pull secret has been sealed. Set `GHCR_DEPLOY_PROD_ENABLED` to `true` only after production images and pull credentials have also been migrated. If these variables are unset or not `true`, image publishing can proceed but GitOps updates stay disabled.

## Required settings in `platform-gitops`

Add repository secrets `GHCR_READ_USERNAME` and `GHCR_READ_TOKEN`. The token must be a classic personal access token with only `read:packages`, and its owner must have access to the private packages. The existing `SEALED_SECRETS_CERT` secret is also required.

Run **Reseal workload secrets** on a non-main review branch with `ghcr-dev` to create pull credentials for dev namespaces, or `ghcr-all` for dev and prod. This workflow reads no Secret Manager values. Review and merge its SealedSecret changes before switching any workload to GHCR.

The published GHCR packages are private by default. Do not enable either deployment variable until the corresponding namespaces contain the generated `ghcr-regcred` Secret and the GitOps image names point at GHCR.
