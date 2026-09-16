#!/bin/sh

set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ci_file="$repo_dir/.gitlab-ci.yml"
seal_script="$repo_dir/ci/seal-secrets.sh"

require_text() {
  file_path="$1"
  expected="$2"

  if ! grep -F -- "$expected" "$file_path" >/dev/null; then
    echo "Missing required secret contract in $file_path: $expected" >&2
    exit 1
  fi
}

# GraphDB is required by the ontology workload. The CI job must fail when the
# GitLab File variable is absent instead of generating an empty SealedSecret.
require_text "$ci_file" 'test -n "${GRAPHDB_LICENSE_FILE:-}"'
require_text "$ci_file" 'test -f "$GRAPHDB_LICENSE_FILE"'
require_text "$seal_script" ': "${GRAPHDB_LICENSE_FILE:?'
require_text "$seal_script" 'prepare_graphdb_license_file'
require_text "$seal_script" 'Decoded Base64 GraphDB license before sealing'
require_text "$seal_script" 'seal_file_secret \'

echo "Sealed Secrets contract: PASS"
