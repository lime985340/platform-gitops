#!/bin/sh

set -eu

: "${APPLICATION:?APPLICATION is required (atmo, neople-game-analytics, ontology-asal-agent, or q-interior)}"
: "${WORKLOAD:?WORKLOAD is required (api or web)}"
: "${ENVIRONMENT:?ENVIRONMENT is required (dev or prod)}"
: "${IMAGE_TAG:?IMAGE_TAG is required}"
: "${CLUSTER:=onprem}"

case "$CLUSTER" in
  onprem|oci-osaka) ;;
  *)
    echo "CLUSTER must be onprem or oci-osaka" >&2
    exit 1
    ;;
esac

case "$APPLICATION" in
  atmo|neople-game-analytics|ontology-asal-agent|q-interior) ;;
  *)
    echo "APPLICATION must be atmo, neople-game-analytics, ontology-asal-agent, or q-interior" >&2
    exit 1
    ;;
esac

case "$WORKLOAD" in
  api|web) ;;
  *)
    echo "WORKLOAD must be api or web" >&2
    exit 1
    ;;
esac

case "$ENVIRONMENT" in
  dev|prod) ;;
  *)
    echo "ENVIRONMENT must be dev or prod" >&2
    exit 1
    ;;
esac

case "$IMAGE_TAG" in
  ''|*[!A-Za-z0-9._-]*)
    echo "IMAGE_TAG contains unsupported characters" >&2
    exit 1
    ;;
esac

file="clusters/${CLUSTER}/workloads/${APPLICATION}/${WORKLOAD}/environments/${ENVIRONMENT}/kustomization.yaml"
test -f "$file" || {
  echo "Image configuration not found: $file" >&2
  exit 1
}

sed -i.bak -E "s/^([[:space:]]+newTag:).*/\\1 ${IMAGE_TAG}/" "$file"
rm -f "${file}.bak"

# Production overlays retain their legacy registry until the service CI
# explicitly selects a published GHCR image for deployment.
if [ -n "${IMAGE_NAME:-}" ]; then
  case "$IMAGE_NAME" in
    ghcr.io/lime985340/*) ;;
    *) echo "IMAGE_NAME must use ghcr.io/lime985340" >&2; exit 1 ;;
  esac
  if grep -q '^[[:space:]]*newName:' "$file"; then
    sed -i.bak -E "s|^([[:space:]]+newName:).*|\\1 ${IMAGE_NAME}|" "$file"
  else
    sed -i.bak -E "s|^([[:space:]]+)newTag:|\\1newName: ${IMAGE_NAME}\\n\\1newTag:|" "$file"
  fi
  rm -f "${file}.bak"
fi

echo "Updated $file to image tag $IMAGE_TAG"
