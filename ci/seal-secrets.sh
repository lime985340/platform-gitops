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

tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_dir"
}

trap cleanup EXIT INT TERM

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

seal_registry_secret() {
  output="$1"
  namespace="$2"
  docker_config="${GITLAB_REGISTRY_DOCKER_CONFIG:-}"
  plain_manifest="$tmp_dir/${namespace}-gitlab-regcred.yaml"
  sealed_manifest="$tmp_dir/${namespace}-gitlab-regcred-sealed.yaml"

  if [ -z "$docker_config" ] || [ ! -f "$docker_config" ]; then
    echo "Missing GitLab File variable: GITLAB_REGISTRY_DOCKER_CONFIG" >&2
    exit 1
  fi

  kubectl create secret generic gitlab-regcred \
    --namespace "$namespace" \
    --type kubernetes.io/dockerconfigjson \
    --from-file=.dockerconfigjson="$docker_config" \
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
