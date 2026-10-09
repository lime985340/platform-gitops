#!/bin/sh
set -eu
case "$Q_ACTION" in deploy-api) workload=api ;; deploy-web) workload=web ;; *) exit 1 ;; esac
case "$Q_ENVIRONMENT" in dev|prod) ;; *) exit 1 ;; esac
overlay="workloads/q-interior/$workload/environments/$Q_ENVIRONMENT"
grep -q 'encryptedData:' "$overlay/sealed-secrets.yaml" || { echo 'Seal Q Interior secrets before enabling deployment' >&2; exit 1; }
if [ "$workload" = api ]; then
  grep -q 'name: q-interior-db-secret' "$overlay/sealed-secrets.yaml" || exit 1
fi
grep -q 'name: gitlab-regcred' "$overlay/sealed-secrets.yaml" || exit 1
image_tag="$Q_SOURCE_SHA"
if [ "$Q_ENVIRONMENT" = prod ]; then image_tag="$Q_SOURCE_REF"; fi
if [ "$workload" = api ]; then
  case "$Q_ENVIRONMENT" in
    dev) neon_host="${Q_INTERIOR_NEON_DEV_HOST:?Neon hostname is required}" ;;
    prod) neon_host="${Q_INTERIOR_NEON_PROD_HOST:?Neon hostname is required}" ;;
  esac
  printf '%s' "$neon_host" | grep -Eq '^[a-z0-9.-]+\.neon\.tech$' || exit 1
  policy="platform/policies/allow-q-interior-api-$Q_ENVIRONMENT-db-egress.yaml"
  sed -i -E "s/(matchName: ).*/\1$neon_host/" "$policy"
  git add "$policy"
  case "$Q_ENVIRONMENT" in
    dev) mail_host="${Q_INTERIOR_SMTP_DEV_HOST:-}" ;;
    prod) mail_host="${Q_INTERIOR_SMTP_PROD_HOST:-}" ;;
  esac
  if [ -n "$mail_host" ]; then
    printf '%s' "$mail_host" | grep -Eq '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$' || exit 1
    mail_policy="platform/policies/allow-q-interior-api-$Q_ENVIRONMENT-mail-egress.yaml"
    sed -i -E "s/(matchName: ).*/\1$mail_host/" "$mail_policy"
    git add "$mail_policy"
  fi
fi
APPLICATION=q-interior WORKLOAD="$workload" ENVIRONMENT="$Q_ENVIRONMENT" IMAGE_TAG="$image_tag" sh ci/update-image-tag.sh
sed -i 's/count: 0/count: 1/' "$overlay/kustomization.yaml"
git config user.name 'gitlab-ci[bot]'
git config user.email 'gitlab-ci[bot]@users.noreply.gitlab.com'
git add "$overlay/kustomization.yaml"
git diff --cached --quiet && exit 0
git commit -m "chore: deploy q-interior $workload $Q_ENVIRONMENT $image_tag"
deploy_branch="codex/deploy-q-interior-$workload-$Q_ENVIRONMENT-$CI_PIPELINE_ID"
umask 077
askpass_file=$(mktemp)
trap 'rm -f "$askpass_file"' EXIT INT TERM
cat > "$askpass_file" <<'ASKPASS'
#!/bin/sh
case "${1-}" in
  *[Uu]sername*) printf '%s\n' gitlab-ci-token ;;
  *[Pp]assword*) printf '%s\n' "$CI_JOB_TOKEN" ;;
  *) exit 1 ;;
esac
ASKPASS
chmod 700 "$askpass_file"
export GIT_ASKPASS="$askpass_file" GIT_TERMINAL_PROMPT=0 LC_ALL=C
unset GIT_TRACE GIT_TRACE2 GIT_TRACE_CURL GIT_CURL_VERBOSE
git -c credential.helper= -c http.followRedirects=false push \
  -o merge_request.create -o merge_request.target=main \
  -o "merge_request.title=deploy: Q Interior $workload $Q_ENVIRONMENT $image_tag" \
  "https://${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git" "HEAD:$deploy_branch"
