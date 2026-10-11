#!/bin/sh
set -eu
test "${CI_DEBUG_TRACE:-false}" != true || { echo 'Debug trace must be disabled' >&2; exit 1; }
case "$Q_SOURCE_SHA" in ''|*[!a-f0-9]*) echo 'Invalid source SHA' >&2; exit 1 ;; esac
test "${#Q_SOURCE_SHA}" -eq 40
case "$Q_ACTION" in
  deploy-api) source_repository=q-interior-api ;;
  deploy-web|android|ios) source_repository=q-interior-client ;;
  *) exit 1 ;;
esac
case "$Q_ENVIRONMENT" in
  dev) test "$Q_SOURCE_REF" = main; source_ref=refs/heads/main ;;
  prod) printf '%s' "$Q_SOURCE_REF" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; source_ref="refs/tags/$Q_SOURCE_REF" ;;
  *) exit 1 ;;
esac
test ! -e q-source || { echo 'q-source already exists' >&2; exit 1; }
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
git init q-source
git -C q-source remote add origin "https://gitlab.com/lime985340/$source_repository.git"
git -C q-source -c credential.helper= -c http.followRedirects=false fetch --depth 1 origin "$source_ref"
actual_sha=$(git -C q-source rev-parse 'FETCH_HEAD^{commit}')
test "$actual_sha" = "$Q_SOURCE_SHA" || { echo 'Source ref changed; rerun the latest pipeline' >&2; exit 1; }
git -C q-source checkout --detach "$actual_sha"
