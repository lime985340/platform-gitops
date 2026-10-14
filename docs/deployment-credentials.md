# Deployment credentials

All eight service repositories store the same `PLATFORM_GITOPS_TOKEN` secret.
It is a fine-grained token restricted to `lime985340/platform-gitops`, with
Contents and Pull requests read/write. GitOps also stores it to seal the Argo
HTTPS repository credential; SSH deploy keys are disabled by repository policy.

| Credential | Purpose | Expiration |
| --- | --- | --- |
| `platform-gitops-ci-20261014` | Service CI GitOps commits/PRs and Argo GitHub access | 2027-10-15 |
| `ghcr-cluster-readonly-20261014` | Cluster image pulls, `read:packages` only | 2027-10-14 |

The classic GHCR token has a maximum 365-day lifetime in GitHub. No token value
is committed to Git; only encrypted SealedSecrets are stored in this repository.

## Renewal

1. Renew the GitOps token with the same repository scope and permissions.
2. Replace `PLATFORM_GITOPS_TOKEN` in the eight service repositories and GitOps.
3. Run **Reseal workload secrets**, scope `argocd-repo`, from a review branch.
4. Merge the encrypted credential change after validation.
5. For GHCR, replace `GHCR_READ_TOKEN` in GitOps; keep `GHCR_READ_USERNAME=siri2677`.
6. Run the resealing workflow with `ghcr-all` from a review branch and merge it.

## Deployment

Both deployment gates are repository variables set to `true` in each service.
Main builds publish a full commit SHA image and update GitHub GitOps dev.
Version tag pushes publish the version image. Manually run service CI with
`release_tag=vMAJOR.MINOR.PATCH` to create a production GitOps PR. Merge that PR
to start Argo deployment. During migration, production overlays retain their
legacy image registry until this manual action selects a verified GHCR image.
