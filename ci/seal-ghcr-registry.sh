#!/bin/sh

set -eu

ghcr_scope="${1:-dev}"
case "$ghcr_scope" in
  dev|all|oci|q-interior-dev|q-interior-prod|atmo-api-dev|atmo-api-prod) ;;
  *) echo "Usage: $0 [dev|all|oci|q-interior-dev|q-interior-prod|atmo-api-dev|atmo-api-prod]" >&2; exit 2 ;;
esac

: "${SEALED_SECRETS_CERT:?SEALED_SECRETS_CERT must point to the controller public certificate}"
: "${GHCR_READ_USERNAME:?GHCR_READ_USERNAME is required}"
: "${GHCR_READ_TOKEN:?GHCR_READ_TOKEN is required}"

for command in kubectl kubeseal jq python3; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "$command is required" >&2
    exit 1
  }
done

test -f "$SEALED_SECRETS_CERT" || {
  echo "SEALED_SECRETS_CERT does not point to a file" >&2
  exit 1
}

umask 077
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT INT TERM
registry_config="$tmp_dir/registry-config.json"

auth="$(printf '%s' "$GHCR_READ_USERNAME:$GHCR_READ_TOKEN" | base64 | tr -d '\n')"
jq -n \
  --arg username "$GHCR_READ_USERNAME" \
  --arg password "$GHCR_READ_TOKEN" \
  --arg auth "$auth" \
  '{auths: {"ghcr.io": {username: $username, password: $password, auth: $auth}}}' \
  > "$registry_config"
unset GHCR_READ_USERNAME GHCR_READ_TOKEN auth

seal_namespace() {
  workload_path="$1"
  namespace="$2"
  cluster="${3:-onprem}"
  output="clusters/$cluster/workloads/$workload_path/environments/$environment/sealed-secrets.yaml"
  plain_manifest="$tmp_dir/${namespace}-ghcr-regcred.yaml"
  sealed_manifest="$tmp_dir/${namespace}-ghcr-regcred-sealed.yaml"
  test -f "$output" || {
    echo "Missing SealedSecret bundle: $output" >&2
    exit 1
  }

  kubectl create secret generic ghcr-regcred \
    --namespace "$namespace" \
    --type kubernetes.io/dockerconfigjson \
    --from-file=.dockerconfigjson="$registry_config" \
    --dry-run=client \
    --output yaml > "$plain_manifest"

  kubeseal \
    --cert "$SEALED_SECRETS_CERT" \
    --format yaml \
    < "$plain_manifest" > "$sealed_manifest"

  # Ontology publication is a Sync hook in wave -1. Pull credentials must
  # decrypt before that hook can start on a newly configured namespace.
  kubectl annotate --local -f "$sealed_manifest" \
    argocd.argoproj.io/sync-wave=-2 --overwrite -o yaml > "$tmp_dir/ordered-sealed.yaml"
  mv "$tmp_dir/ordered-sealed.yaml" "$sealed_manifest"

  python3 - "$output" "$sealed_manifest" <<'PY'
import pathlib
import re
import sys

target = pathlib.Path(sys.argv[1])
sealed = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8").strip()
sealed = re.sub(r"\A---[ \t]*\r?\n", "", sealed)
marker = "# Managed by ci/seal-ghcr-registry.sh"
content = target.read_text(encoding="utf-8")
documents = re.split(r"(?m)^---[ \t]*\r?$", content)
kept = [document.strip() for document in documents
        if marker not in document and not re.search(r"(?m)^  name: ghcr-regcred[ \t]*$", document)]
base = "\n---\n".join(document for document in kept if document)
replacement = f"{marker}\n{sealed}"
updated = f"{base}\n---\n{replacement}\n" if base else f"{replacement}\n"
target.write_text(updated, encoding="utf-8", newline="\n")
PY

  echo "Generated encrypted GHCR pull Secret for namespace $namespace"
}

seal_environment() {
  environment="$1"
  seal_namespace atmo/api "atmo-api-$environment"
  seal_namespace atmo/web "atmo-web-$environment"
  seal_namespace neople-game-analytics/api "neople-game-analytics-api-$environment"
  seal_namespace neople-game-analytics/web "neople-game-analytics-web-$environment"
  seal_namespace ontology-asal-agent/api "ontology-asal-agent-api-$environment"
  seal_namespace ontology-asal-agent/web "ontology-asal-agent-web-$environment"
  seal_namespace q-interior/api "q-interior-api-$environment"
  seal_namespace q-interior/web "q-interior-web-$environment"
}

seal_q_interior_environment() {
  environment="$1"
  seal_namespace q-interior/api "q-interior-api-$environment"
  seal_namespace q-interior/web "q-interior-web-$environment"
}

seal_atmo_api_environment() {
  environment="$1"
  seal_namespace atmo/api "atmo-api-$environment"
}

seal_oci_environment() {
  environment="$1"
  seal_namespace atmo/api "atmo-api-$environment" oci-osaka
  seal_namespace atmo/web "atmo-web-$environment" oci-osaka
  seal_namespace neople-game-analytics/api "neople-game-analytics-api-$environment" oci-osaka
  seal_namespace neople-game-analytics/web "neople-game-analytics-web-$environment" oci-osaka
  seal_namespace ontology-asal-agent/api "ontology-asal-agent-api-$environment" oci-osaka
  seal_namespace ontology-asal-agent/web "ontology-asal-agent-web-$environment" oci-osaka
  seal_namespace q-interior/api "q-interior-api-$environment" oci-osaka
  seal_namespace q-interior/web "q-interior-web-$environment" oci-osaka
}

case "$ghcr_scope" in
  dev)
    seal_environment dev
    ;;
  all)
    seal_environment dev
    seal_environment prod
    ;;
  q-interior-dev)
    seal_q_interior_environment dev
    ;;
  q-interior-prod)
    seal_q_interior_environment prod
    ;;
  atmo-api-dev)
    seal_atmo_api_environment dev
    ;;
  atmo-api-prod)
    seal_atmo_api_environment prod
    ;;
  oci)
    seal_oci_environment dev
    seal_oci_environment prod
    ;;
esac

rm -rf "$tmp_dir"
trap - EXIT INT TERM
