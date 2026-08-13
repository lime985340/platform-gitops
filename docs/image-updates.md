# Image tag updates

The service repository should update the GitOps image tag after it builds and
pushes a new image. Image Updater is not required for this repository.

The reusable script updates one environment file and does not commit or push
by itself:

~~~bash
WORKLOAD=api \
ENVIRONMENT=dev \
IMAGE_TAG=dev-abc1234 \
sh ci/update-image-tag.sh
~~~

The supported paths are:

~~~text
workloads/atmo/api/environments/dev/kustomization.yaml
workloads/atmo/api/environments/prod/kustomization.yaml
workloads/atmo/web/environments/dev/kustomization.yaml
workloads/atmo/web/environments/prod/kustomization.yaml
~~~

## Current Atmo service CI flow

The `atmo-api` and `atmo-web` repositories now use the same two follow-up CI
jobs after their Docker jobs:

- `gitops:update-dev` runs for the `dev` branch and updates the matching `dev`
  Kustomize tag.
- `gitops:update-prod` runs for a semantic version tag such as `v0.2.5` and
  updates the matching `prod` Kustomize tag.

Both jobs use the GitOps branch from `GITOPS_BRANCH`, which currently defaults
to `feature/clean-gitops-layout` while this branch is being tested. The
variable can later be changed to `main` after the GitOps changes are merged.

Each service repository needs the following masked CI/CD variable:

```text
GITOPS_PUSH_TOKEN
```

The token needs `write_repository` permission on the GitOps repository. The
service CI does not need Kubernetes access, a kubeconfig, or Argo CD access.
The generated GitOps commit uses `[skip ci]`, so it does not create a loop in
the GitOps validation pipeline.

## Manual service CI flow

The service repository can clone this repository after publishing its image,
run the script, and push the resulting Git change:

~~~bash
git clone --branch "$GITOPS_BRANCH" \
  "https://oauth2:${GITOPS_PUSH_TOKEN}@gitlab.com/lime985340/gitops.git" \
  gitops

cd gitops
WORKLOAD=api ENVIRONMENT=dev IMAGE_TAG="$CI_COMMIT_SHORT_SHA" \
  sh ci/update-image-tag.sh

git config user.name "gitlab-ci[bot]"
git config user.email "gitlab-ci[bot]@users.noreply.gitlab.com"
git add workloads/atmo/api/environments/dev/kustomization.yaml
git commit -m "chore: deploy atmo-api ${CI_COMMIT_SHORT_SHA} [skip ci]"
git push origin "$GITOPS_BRANCH"
~~~

The service repository needs a masked GITOPS_PUSH_TOKEN with
write_repository permission and a GITOPS_BRANCH variable. Use
feature/clean-gitops-layout while testing this branch and change it to main
after the GitOps changes are merged.

The GitOps CI then validates the changed Kustomize output, and Argo CD detects
the commit and deploys the new image. The GitOps repository does not need
access to the service repository.
