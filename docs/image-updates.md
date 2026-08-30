# Image tag updates

The service repository should update the GitOps image tag after it builds and
pushes a new image. Image Updater is not required for this repository.

The reusable script updates one environment file and does not commit or push
by itself:

~~~bash
APPLICATION=atmo \
WORKLOAD=api \
ENVIRONMENT=dev \
IMAGE_TAG=abc1234567890abcdef1234567890abcdef123456 \
sh ci/update-image-tag.sh
~~~

Neople Game Analytics uses the same script with an explicit application name:

~~~bash
APPLICATION=neople-game-analytics \
WORKLOAD=api \
ENVIRONMENT=dev \
IMAGE_TAG=abc1234567890abcdef1234567890abcdef123456 \
sh ci/update-image-tag.sh

APPLICATION=neople-game-analytics \
WORKLOAD=web \
ENVIRONMENT=dev \
IMAGE_TAG=abc1234567890abcdef1234567890abcdef123456 \
sh ci/update-image-tag.sh
~~~

The Neople API Deployment and its daily Worker CronJob intentionally reuse the
same `neople-game-analytics-api` image. The Worker changes only the container
command to `python -m src.pipeline`; it does not require a second `/worker`
image repository or a second image tag entry.

Ontology ASAL Agent uses the same script for its split API and Web repositories:

~~~bash
APPLICATION=ontology-asal-agent \
WORKLOAD=web \
ENVIRONMENT=dev \
IMAGE_TAG=abc1234567890abcdef1234567890abcdef123456 \
sh ci/update-image-tag.sh
~~~

The supported paths are:

~~~text
workloads/atmo/api/environments/dev/kustomization.yaml
workloads/atmo/api/environments/prod/kustomization.yaml
workloads/atmo/web/environments/dev/kustomization.yaml
workloads/atmo/web/environments/prod/kustomization.yaml
workloads/neople-game-analytics/api/environments/dev/kustomization.yaml
workloads/neople-game-analytics/api/environments/prod/kustomization.yaml
workloads/neople-game-analytics/web/environments/dev/kustomization.yaml
workloads/neople-game-analytics/web/environments/prod/kustomization.yaml
workloads/ontology-asal-agent/api/environments/dev/kustomization.yaml
workloads/ontology-asal-agent/api/environments/prod/kustomization.yaml
workloads/ontology-asal-agent/web/environments/dev/kustomization.yaml
workloads/ontology-asal-agent/web/environments/prod/kustomization.yaml
~~~

## Neople Game Analytics service branch flow

The Neople service repository uses `main` and `feature/*` branches. It does not
use a service-repository `dev` branch.

- A `feature/*` branch runs tests only.
- A `main` commit builds the API/Worker image and Web image once, pushes both
  with the full commit SHA, and updates the Neople `dev` overlay.
- A semantic version tag such as `v0.2.5` verifies that the tagged commit's
  SHA images exist, adds the version tag to those existing image manifests
  without rebuilding, and updates the Neople `prod` overlay.

The `dev` path above is a Kubernetes environment, not a Git branch. API and
Worker share one image, so the Neople application has two physical image
repositories: API/Worker and Web.

The Ontology ASAL Agent API and Web repositories follow the same `main` and
`feature/*` flow as Neople: feature branches run tests only; a `main` commit
builds once with the full commit SHA and updates the matching `dev` overlay;
semantic release tags promote that existing SHA image without rebuilding and
update the matching `prod` overlay. The API migration Job reuses the API image.

## Current Atmo service CI flow

The `atmo-api` and `atmo-web` repositories use the same CI contract as Neople:

- The default branch (`main`) builds once with the full commit SHA, pushes the
  image, and updates the `dev` Kustomize tag.
- A semantic version tag such as `v0.2.5` verifies the existing SHA image,
  adds the version tag without rebuilding, and updates the `prod` Kustomize
  tag.

The CI job names are `build_images`, `promote_release`, `update_gitops_dev`,
and `update_gitops_prod` in both service repositories.

Both jobs use the GitOps branch from `GITOPS_BRANCH`, which currently defaults
to `feature/clean-gitops-layout` while this branch is being tested. The
variable can later be changed to `main` after the GitOps changes are merged.

Each service repository inherits the following CI/CD variables from the
`lime985340` Group:

```text
GITOPS_PUSH_TOKEN
GITOPS_PUSH_TOKEN_USER
GITOPS_BRANCH
```

These variables are used
only by the service repositories' cross-project image-update jobs. The GitOps
repository's own `seal:workload-secrets` job uses the predefined `CI_JOB_TOKEN`
instead and does not use these Group variables.

While the GitOps feature branch is being tested, set the inherited
`GITOPS_BRANCH` to `feature/clean-gitops-layout`; change this one Group Variable
to `main` after the GitOps changes are merged. The service jobs allow only
`feature/clean-gitops-layout` and `main` as target branches.

The service variables are intentionally Group-level rather than duplicated in
each service project. Keep the token protected with the selected service refs,
and ensure the token identity is allowed to push the protected GitOps branch.
The `GITOPS_PUSH_TOKEN_USER` value must match the username generated for the
chosen token type. Do not print either token variable in CI logs.

The GitOps sealing flow is separate. Its project-level variables are
`SEALED_SECRETS_CERT`, the `ATMO_API_*_ENV` File variables, and the Registry
username/token pair described in [secret-variables.md](secret-variables.md).
The GitOps project does not need a duplicate `GITOPS_*` variable for sealing.
The service image-update variables are not Registry credentials, and Registry
credentials are not used for Git pushes.

The service repositories need no Kubernetes, kubeconfig, or Argo CD access for
this flow. The generated GitOps commit intentionally runs the lightweight
manifest validation pipeline, so a tag update cannot bypass Kustomize checks.
The validation pipeline does not push changes and therefore cannot create a
validation loop. Current image tags remain usable until a service publishes a
replacement; no service image needs to be rebuilt merely because the GitOps
feature branch exists.

## Manual service CI flow

The service repository can clone this repository after publishing its image,
run the script, and push the resulting Git change. Do not put the token in the
clone URL: Git stores a credential-bearing URL in the cloned repository's
`.git/config`.

The following Alpine-compatible example uses a temporary `GIT_ASKPASS` helper.
The helper file contains no token; Git reads the token from the environment
only when it requests a password:

~~~bash
set -eu
umask 077
: "${GITOPS_PUSH_TOKEN:?GITOPS_PUSH_TOKEN is required}"
: "${GITOPS_PUSH_TOKEN_USER:?GITOPS_PUSH_TOKEN_USER is required}"
: "${GITOPS_BRANCH:?GITOPS_BRANCH is required}"

case "$GITOPS_BRANCH" in
  feature/clean-gitops-layout|main) ;;
  *) printf '%s\n' 'Unsupported GitOps branch' >&2; exit 1 ;;
esac

askpass_file="$(mktemp)"
cleanup() { rm -f "$askpass_file"; }
trap cleanup EXIT INT TERM
cat > "$askpass_file" <<'ASKPASS'
#!/bin/sh
case "${1-}" in
  *[Uu]sername*) printf '%s\n' "$GITOPS_PUSH_TOKEN_USER" ;;
  *[Pp]assword*) printf '%s\n' "$GITOPS_PUSH_TOKEN" ;;
  *) exit 1 ;;
esac
ASKPASS
chmod 700 "$askpass_file"

export GIT_ASKPASS="$askpass_file"
export GIT_TERMINAL_PROMPT=0
export LC_ALL=C
unset GIT_TRACE GIT_TRACE2 GIT_TRACE_CURL GIT_CURL_VERBOSE

git -c credential.helper= -c http.followRedirects=false \
  clone --branch "$GITOPS_BRANCH" \
  https://gitlab.com/lime985340/gitops.git gitops

cd gitops
APPLICATION=atmo WORKLOAD=api ENVIRONMENT=dev IMAGE_TAG="$CI_COMMIT_SHA" \
  sh ci/update-image-tag.sh

git config user.name "gitlab-ci[bot]"
git config user.email "gitlab-ci[bot]@users.noreply.gitlab.com"
git add workloads/atmo/api/environments/dev/kustomization.yaml
git commit -m "chore: deploy atmo-api ${CI_COMMIT_SHA}"
git -c credential.helper= -c http.followRedirects=false \
  push origin "HEAD:$GITOPS_BRANCH"
~~~

`GITOPS_PUSH_TOKEN_USER` must match the generated username for the token
type: use the Project Access Token username for a project token; `oauth2` is
appropriate for OAuth-style credentials, not a universal username. The token
needs `write_repository` permission on the GitOps repository. `write_repository`
does not bypass Protected branch rules, so the token identity must also be
allowed to push the selected branch. Protected variables are unavailable on
unprotected refs; protect the service refs that run these jobs or use an
appropriate protected release ref before enabling Protected on the variables.

Keep `CI_DEBUG_TRACE`, `set -x`, and all Git tracing disabled. Do not print the
token, certificate, plaintext Secret, or kubeconfig, and do not store them in
artifacts. The GitOps CI validates the changed Kustomize output, and Argo CD
detects the commit and deploys the new image. The GitOps repository does not
need access to the service repository.
