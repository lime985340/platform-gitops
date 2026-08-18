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

Each service repository needs the following CI/CD variables:

```text
GITOPS_PUSH_TOKEN
GITOPS_PUSH_TOKEN_USER
GITOPS_BRANCH
```

`GITOPS_PUSH_TOKEN` and `GITOPS_PUSH_TOKEN_USER` are ordinary single-line
`Variable` values, not `File` variables. The token should be Masked only when
GitLab's masking constraints allow it. `GITOPS_PUSH_TOKEN_USER` is not secret in
the same way, but keep it protected with the token and do not print it
unnecessarily. `GITOPS_BRANCH` is a non-secret Variable; while this feature
branch is being tested, set it to `feature/clean-gitops-layout`.
The token needs `write_repository` permission on the GitOps repository. The
service CI does not need Kubernetes access, a kubeconfig, or Argo CD access.
The generated GitOps commit uses `[skip ci]`, so it does not create a loop in
the GitOps validation pipeline.

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
WORKLOAD=api ENVIRONMENT=dev IMAGE_TAG="$CI_COMMIT_SHORT_SHA" \
  sh ci/update-image-tag.sh

git config user.name "gitlab-ci[bot]"
git config user.email "gitlab-ci[bot]@users.noreply.gitlab.com"
git add workloads/atmo/api/environments/dev/kustomization.yaml
git commit -m "chore: deploy atmo-api ${CI_COMMIT_SHORT_SHA} [skip ci]"
git -c credential.helper= -c http.followRedirects=false \
  push origin "$GITOPS_BRANCH"
~~~

`GITOPS_PUSH_TOKEN_USER` must match the generated username for the token
type: use the Project Access Token username for a project token; `oauth2` is
appropriate for OAuth-style credentials, not a universal username. The token
needs `write_repository` permission on the GitOps repository. `write_repository`
does not bypass Protected branch rules, so the token identity must also be
allowed to push the selected branch. Protected variables are unavailable on
unprotected refs; protect the test branch or run this flow from the protected
release branch before enabling Protected on the variables.

Keep `CI_DEBUG_TRACE`, `set -x`, and all Git tracing disabled. Do not print the
token, certificate, plaintext Secret, or kubeconfig, and do not store them in
artifacts. The GitOps CI then validates the changed Kustomize output, and Argo
CD detects the commit and deploys the new image. The GitOps repository does not
need access to the service repository.
