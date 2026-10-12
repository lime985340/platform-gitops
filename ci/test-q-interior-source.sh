#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_script="$script_dir/q-interior-source.sh"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

cat > "$tmp_dir/git" <<'GIT'
#!/bin/sh
echo 'Unexpected Git command; source repository access is not part of deployment' >&2
exit 97
GIT
chmod 700 "$tmp_dir/git"
export PATH="$tmp_dir:$PATH"

sha=0123456789abcdef0123456789abcdef01234567
valid() {
  CI_PIPELINE_SOURCE=pipeline CI_DEBUG_TRACE=false \
    Q_ACTION="$1" Q_ENVIRONMENT="$2" Q_SOURCE_REF="$3" Q_SOURCE_SHA="$4" \
    sh "$source_script" >/dev/null
}
invalid() {
  if CI_PIPELINE_SOURCE="$1" CI_DEBUG_TRACE=false \
    Q_ACTION="$2" Q_ENVIRONMENT="$3" Q_SOURCE_REF="$4" Q_SOURCE_SHA="$5" \
    sh "$source_script" >/dev/null 2>&1; then
    echo 'Invalid source identity was accepted' >&2
    exit 1
  fi
}

valid deploy-api dev main "$sha"
valid deploy-web dev main "$sha"
valid deploy-web prod v1.2.3 "$sha"
invalid web deploy-web dev main "$sha"
invalid pipeline deploy-api dev feature "$sha"
invalid pipeline deploy-web prod main "$sha"
invalid pipeline deploy-api dev main 0123456789abcdef

echo 'Q Interior source identity validation: PASS'
