#!/bin/sh

set -eu

: "${SEALED_SECRETS_CERT:?SEALED_SECRETS_CERT must point to the controller public certificate}"

if [ ! -f "$SEALED_SECRETS_CERT" ]; then
  echo "SEALED_SECRETS_CERT does not point to a file" >&2
  exit 1
fi

command -v kubectl >/dev/null 2>&1 || {
  echo "kubectl is required" >&2
  exit 1
}

command -v kubeseal >/dev/null 2>&1 || {
  echo "kubeseal is required" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || {
  echo "jq is required" >&2
  exit 1
}

: "${GITLAB_REGISTRY_USERNAME:?GITLAB_REGISTRY_USERNAME is required}"
: "${GITLAB_REGISTRY_TOKEN:?GITLAB_REGISTRY_TOKEN is required}"

umask 077
tmp_dir="$(mktemp -d)"
registry_config="$tmp_dir/registry-config.json"

cleanup() {
  rm -rf "$tmp_dir"
}

trap cleanup EXIT INT TERM

if ! jq -n \
  '{auths: {"registry.gitlab.com": {
    username: env.GITLAB_REGISTRY_USERNAME,
    password: env.GITLAB_REGISTRY_TOKEN,
    auth: ((env.GITLAB_REGISTRY_USERNAME + ":" + env.GITLAB_REGISTRY_TOKEN) | @base64)
  }}}' \
  > "$registry_config"; then
  echo "Failed to create the temporary registry configuration" >&2
  exit 1
fi

if [ ! -s "$registry_config" ]; then
  echo "Temporary registry configuration is empty" >&2
  exit 1
fi

unset GITLAB_REGISTRY_USERNAME GITLAB_REGISTRY_TOKEN

# Keep the generated config only until all registry SealedSecrets are created.

reject_placeholder_file() {
  file_path="$1"
  variable_name="$2"

  if [ -f "$file_path" ] && grep -Eq 'REPLACE_WITH_[A-Z0-9_]+|PLACEHOLDER_ONLY' "$file_path"; then
    echo "${variable_name} contains a placeholder; replace it with the real value before sealing" >&2
    exit 1
  fi
}

append_sealed() {
  output="$1"
  sealed_manifest="$2"

  if [ -s "$output" ]; then
    printf '%s\n' '---' >> "$output"
  fi

  cat "$sealed_manifest" >> "$output"
}

seal_env_secret() {
  output="$1"
  namespace="$2"
  name="$3"
  env_file="$4"
  plain_manifest="$tmp_dir/${namespace}-${name}.yaml"
  sealed_manifest="$tmp_dir/${namespace}-${name}-sealed.yaml"

  if [ -z "$env_file" ] || [ ! -f "$env_file" ]; then
    echo "Missing GitLab File variable for ${namespace}/${name}" >&2
    exit 1
  fi

  kubectl create secret generic "$name" \
    --namespace "$namespace" \
    --from-env-file "$env_file" \
    --dry-run=client \
    --output yaml > "$plain_manifest"

  kubeseal \
    --cert "$SEALED_SECRETS_CERT" \
    --format yaml \
    < "$plain_manifest" > "$sealed_manifest"

  append_sealed "$output" "$sealed_manifest"
  echo "Generated encrypted SealedSecret ${namespace}/${name}"
}

seal_env_secret_if_configured() {
  output="$1"
  namespace="$2"
  name="$3"
  env_file="$4"

  if [ -z "$env_file" ]; then
    echo "Skipping optional SealedSecret ${namespace}/${name}"
    return 0
  fi

  reject_placeholder_file "$env_file" "${namespace}/${name}"
  seal_env_secret "$output" "$namespace" "$name" "$env_file"
}

seal_file_secret() {
  output="$1"
  namespace="$2"
  name="$3"
  key="$4"
  file_path="$5"
  plain_manifest="$tmp_dir/${namespace}-${name}.yaml"
  sealed_manifest="$tmp_dir/${namespace}-${name}-sealed.yaml"

  if [ ! -f "$file_path" ]; then
    echo "Missing GitLab File variable for ${namespace}/${name}" >&2
    exit 1
  fi

  kubectl create secret generic "$name" \
    --namespace "$namespace" \
    --from-file="${key}=${file_path}" \
    --dry-run=client \
    --output yaml > "$plain_manifest"

  kubeseal \
    --cert "$SEALED_SECRETS_CERT" \
    --format yaml \
    < "$plain_manifest" > "$sealed_manifest"

  append_sealed "$output" "$sealed_manifest"
  echo "Generated encrypted SealedSecret ${namespace}/${name}"
}

seal_file_secret_if_configured() {
  output="$1"
  namespace="$2"
  name="$3"
  key="$4"
  file_path="$5"

  if [ -z "$file_path" ]; then
    echo "Skipping optional SealedSecret ${namespace}/${name}"
    return 0
  fi

  reject_placeholder_file "$file_path" "${namespace}/${name}"
  : > "$output"
  seal_file_secret "$output" "$namespace" "$name" "$key" "$file_path"
}

seal_registry_secret() {
  output="$1"
  namespace="$2"
  plain_manifest="$tmp_dir/${namespace}-gitlab-regcred.yaml"
  sealed_manifest="$tmp_dir/${namespace}-gitlab-regcred-sealed.yaml"

  kubectl create secret generic gitlab-regcred \
    --namespace "$namespace" \
    --type kubernetes.io/dockerconfigjson \
    --from-file=.dockerconfigjson="$registry_config" \
    --dry-run=client \
    --output yaml > "$plain_manifest"

  kubeseal \
    --cert "$SEALED_SECRETS_CERT" \
    --format yaml \
    < "$plain_manifest" > "$sealed_manifest"

  append_sealed "$output" "$sealed_manifest"
  echo "Generated encrypted SealedSecret ${namespace}/gitlab-regcred"
}

dev_api_output="workloads/atmo/api/environments/dev/sealed-secrets.yaml"
prod_api_output="workloads/atmo/api/environments/prod/sealed-secrets.yaml"
dev_web_output="workloads/atmo/web/environments/dev/sealed-secrets.yaml"
prod_web_output="workloads/atmo/web/environments/prod/sealed-secrets.yaml"
dev_neople_api_output="workloads/neople-game-analytics/api/environments/dev/sealed-secrets.yaml"
prod_neople_api_output="workloads/neople-game-analytics/api/environments/prod/sealed-secrets.yaml"
dev_neople_web_output="workloads/neople-game-analytics/web/environments/dev/sealed-secrets.yaml"
prod_neople_web_output="workloads/neople-game-analytics/web/environments/prod/sealed-secrets.yaml"
dev_ontology_agent_output="workloads/ontology-asal-agent/api/environments/dev/sealed-secrets.yaml"
prod_ontology_agent_output="workloads/ontology-asal-agent/api/environments/prod/sealed-secrets.yaml"
dev_ontology_agent_web_output="workloads/ontology-asal-agent/web/environments/dev/sealed-secrets.yaml"
prod_ontology_agent_web_output="workloads/ontology-asal-agent/web/environments/prod/sealed-secrets.yaml"
graphdb_license_output="platform/graphdb/sealed-secret.yaml"

: > "$dev_api_output"
seal_env_secret "$dev_api_output" atmo-api-dev atmo-db-secret "${ATMO_API_DEV_DB_ENV:-}"
seal_env_secret "$dev_api_output" atmo-api-dev atmo-jwt-secret "${ATMO_API_DEV_JWT_ENV:-}"
seal_env_secret "$dev_api_output" atmo-api-dev atmo-oauth-secret "${ATMO_API_DEV_OAUTH_ENV:-}"
seal_env_secret "$dev_api_output" atmo-api-dev atmo-publicdata-secret "${ATMO_API_DEV_PUBLICDATA_ENV:-}"
seal_registry_secret "$dev_api_output" atmo-api-dev

: > "$prod_api_output"
seal_env_secret "$prod_api_output" atmo-api-prod atmo-db-secret "${ATMO_API_PROD_DB_ENV:-}"
seal_env_secret "$prod_api_output" atmo-api-prod atmo-jwt-secret "${ATMO_API_PROD_JWT_ENV:-}"
seal_env_secret "$prod_api_output" atmo-api-prod atmo-oauth-secret "${ATMO_API_PROD_OAUTH_ENV:-}"
seal_env_secret "$prod_api_output" atmo-api-prod atmo-publicdata-secret "${ATMO_API_PROD_PUBLICDATA_ENV:-}"
seal_registry_secret "$prod_api_output" atmo-api-prod

: > "$dev_web_output"
seal_registry_secret "$dev_web_output" atmo-web-dev

: > "$prod_web_output"
seal_registry_secret "$prod_web_output" atmo-web-prod

: > "$dev_neople_api_output"
seal_env_secret \
  "$dev_neople_api_output" \
  neople-game-analytics-api-dev \
  neople-game-analytics-api-secret \
  "${NEOPLE_GAME_ANALYTICS_API_DEV_ENV:-}"
seal_registry_secret "$dev_neople_api_output" neople-game-analytics-api-dev

: > "$prod_neople_api_output"
seal_env_secret \
  "$prod_neople_api_output" \
  neople-game-analytics-api-prod \
  neople-game-analytics-api-secret \
  "${NEOPLE_GAME_ANALYTICS_API_PROD_ENV:-}"
seal_registry_secret "$prod_neople_api_output" neople-game-analytics-api-prod

: > "$dev_neople_web_output"
seal_registry_secret "$dev_neople_web_output" neople-game-analytics-web-dev

: > "$prod_neople_web_output"
seal_registry_secret "$prod_neople_web_output" neople-game-analytics-web-prod

: > "$dev_ontology_agent_output"
seal_env_secret_if_configured \
  "$dev_ontology_agent_output" \
  ontology-asal-agent-api-dev \
  ontology-asal-agent-secrets \
  "${ONTOLOGY_ASAL_AGENT_DEV_ENV:-}"
seal_registry_secret "$dev_ontology_agent_output" ontology-asal-agent-api-dev

: > "$prod_ontology_agent_output"
seal_env_secret_if_configured \
  "$prod_ontology_agent_output" \
  ontology-asal-agent-api-prod \
  ontology-asal-agent-secrets \
  "${ONTOLOGY_ASAL_AGENT_PROD_ENV:-}"
seal_registry_secret "$prod_ontology_agent_output" ontology-asal-agent-api-prod

: > "$dev_ontology_agent_web_output"
seal_registry_secret "$dev_ontology_agent_web_output" ontology-asal-agent-web-dev

: > "$prod_ontology_agent_web_output"
seal_registry_secret "$prod_ontology_agent_web_output" ontology-asal-agent-web-prod

seal_file_secret_if_configured \
  "$graphdb_license_output" \
  graphdb \
  graphdb-license \
  graphdb.license \
  "${GRAPHDB_LICENSE_FILE:-}"
