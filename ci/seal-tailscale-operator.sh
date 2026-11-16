#!/usr/bin/env sh
set -eu

: "${TAILSCALE_OAUTH_CLIENT_ID_FILE:?Missing the Tailscale OAuth client ID file}"
: "${TAILSCALE_OAUTH_CLIENT_SECRET_FILE:?Missing the Tailscale OAuth client secret file}"
: "${SEALED_SECRETS_CERT:?Missing the OCI Osaka Sealed Secrets certificate}"

test -s "$TAILSCALE_OAUTH_CLIENT_ID_FILE"
test -s "$TAILSCALE_OAUTH_CLIENT_SECRET_FILE"
test -s "$SEALED_SECRETS_CERT"

output='clusters/oci-osaka/platform/networking/tailscale-operator/sealed-secret.yaml'
mkdir -p "$(dirname "$output")"
umask 077
sealed_tmp="$(mktemp "${output}.XXXXXX")"
annotated_tmp="${sealed_tmp}.annotated"
trap 'rm -f "$sealed_tmp" "$annotated_tmp"' EXIT

kubectl create secret generic operator-oauth \
  --namespace tailscale \
  --from-file=client_id="$TAILSCALE_OAUTH_CLIENT_ID_FILE" \
  --from-file=client_secret="$TAILSCALE_OAUTH_CLIENT_SECRET_FILE" \
  --dry-run=client \
  --output yaml \
  | kubeseal --cert "$SEALED_SECRETS_CERT" --format yaml > "$sealed_tmp"

kubectl annotate --local --filename "$sealed_tmp" \
  argocd.argoproj.io/sync-wave=-2 \
  --overwrite \
  --output yaml > "$annotated_tmp"

mv "$annotated_tmp" "$output"
echo 'Created the encrypted OCI Tailscale Operator SealedSecret.'
