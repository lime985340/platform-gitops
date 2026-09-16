#!/bin/sh

set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ci_file="$repo_dir/.gitlab-ci.yml"
seal_script="$repo_dir/ci/seal-secrets.sh"
secure_files_manifest="$repo_dir/ci/secret-files.conf"

require_text() {
  file_path="$1"
  expected="$2"

  if ! grep -F -- "$expected" "$file_path" >/dev/null; then
    echo "Missing required secret contract in $file_path: $expected" >&2
    exit 1
  fi
}

require_text "$ci_file" 'apk add --no-cache curl git glab jq tar'
require_text "$ci_file" 'glab auth login'
require_text "$ci_file" 'securefile download'
require_text "$ci_file" 'done < ci/secret-files.conf'
require_text "$seal_script" ': "${SECURE_FILES_DIR:?'
require_text "$seal_script" 'secret_file_manifest="${SECRET_FILE_MANIFEST:-ci/secret-files.conf}"'
require_text "$seal_script" 'Secure File was not downloaded'
require_text "$seal_script" 'seal_file_secret() {'
require_text "$secure_files_manifest" 'LIME_GRAPHDB_FREE_v11.3.license|graphdb|graphdb-license|graphdb.license|platform/graphdb/sealed-secret.yaml'

if grep -F 'GRAPHDB_LICENSE_FILE' "$ci_file" "$seal_script" "$secure_files_manifest" >/dev/null; then
  echo "GraphDB-specific CI variable handling must not be hardcoded" >&2
  exit 1
fi

echo "Sealed Secrets contract: PASS"
