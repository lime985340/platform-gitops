#!/bin/sh

set -eu

scope="${SECRET_SCOPE:-all}"
tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_dir"
}

trap cleanup EXIT INT TERM

apply_env_secret() {
  namespace="$1"
  name="$2"
  env_file="$3"
  manifest="$tmp_dir/${namespace}-${name}.yaml"

  if [ -z "$env_file" ] || [ ! -f "$env_file" ]; then
    echo "Missing GitLab File variable for ${namespace}/${name}" >&2
    exit 1
  fi

  kubectl create secret generic "$name" \
    --namespace "$namespace" \
    --from-env-file "$env_file" \
    --dry-run=client \
    --output yaml > "$manifest"

  kubectl apply --filename "$manifest" > /dev/null
  echo "Updated Secret ${namespace}/${name}"
}

apply_registry_secret() {
  namespace="$1"
  manifest="$tmp_dir/${namespace}-gitlab-regcred.yaml"
  docker_config="${GITLAB_REGISTRY_DOCKER_CONFIG:-}"

  if [ -z "$docker_config" ] || [ ! -f "$docker_config" ]; then
    echo "Missing GitLab File variable: GITLAB_REGISTRY_DOCKER_CONFIG" >&2
    exit 1
  fi

  kubectl create secret generic gitlab-regcred \
    --namespace "$namespace" \
    --type kubernetes.io/dockerconfigjson \
    --from-file=.dockerconfigjson="$docker_config" \
    --dry-run=client \
    --output yaml > "$manifest"

  kubectl apply --filename "$manifest" > /dev/null
  echo "Updated Secret ${namespace}/gitlab-regcred"
}

apply_platform_secrets() {
  ghcr_username="${PLATFORM_GHCR_USERNAME:-}"
  ghcr_token="${PLATFORM_GHCR_TOKEN:-}"

  if [ -z "$ghcr_username" ] || [ -z "$ghcr_token" ]; then
    echo "Missing GitLab variables: PLATFORM_GHCR_USERNAME and PLATFORM_GHCR_TOKEN" >&2
    exit 1
  fi

  ghcr_env="$tmp_dir/ghcr-repo-creds.env"
  printf 'url=https://ghcr.io\ntype=helm\nusername=%s\npassword=%s\nenableOCI=true\n' \
    "$ghcr_username" "$ghcr_token" > "$ghcr_env"
  apply_env_secret argocd ghcr-repo-creds "$ghcr_env"
  kubectl label secret ghcr-repo-creds \
    --namespace argocd \
    argocd.argoproj.io/secret-type=repo-creds \
    --overwrite > /dev/null
}

apply_workload_secrets() {
  apply_env_secret atmo-api-dev atmo-db-secret "${ATMO_API_DEV_DB_ENV:-}"
  apply_env_secret atmo-api-dev atmo-jwt-secret "${ATMO_API_DEV_JWT_ENV:-}"
  apply_env_secret atmo-api-dev atmo-oauth-secret "${ATMO_API_DEV_OAUTH_ENV:-}"
  apply_env_secret atmo-api-dev atmo-publicdata-secret "${ATMO_API_DEV_PUBLICDATA_ENV:-}"
  apply_registry_secret atmo-api-dev

  apply_env_secret atmo-api-prod atmo-db-secret "${ATMO_API_PROD_DB_ENV:-}"
  apply_env_secret atmo-api-prod atmo-jwt-secret "${ATMO_API_PROD_JWT_ENV:-}"
  apply_env_secret atmo-api-prod atmo-oauth-secret "${ATMO_API_PROD_OAUTH_ENV:-}"
  apply_env_secret atmo-api-prod atmo-publicdata-secret "${ATMO_API_PROD_PUBLICDATA_ENV:-}"
  apply_registry_secret atmo-api-prod

  apply_registry_secret atmo-web-dev
  apply_registry_secret atmo-web-prod
}

case "$scope" in
  platform)
    apply_platform_secrets
    ;;
  workloads)
    apply_workload_secrets
    ;;
  all)
    apply_platform_secrets
    apply_workload_secrets
    ;;
  *)
    echo "SECRET_SCOPE must be platform, workloads, or all" >&2
    exit 1
    ;;
esac
