#!/bin/sh

set -eu

: "${APPLICATION:=atmo}"
: "${WORKLOAD:?WORKLOAD is required (api or web)}"
: "${ENVIRONMENT:?ENVIRONMENT is required (dev or prod)}"
: "${IMAGE_TAG:?IMAGE_TAG is required}"

case "$APPLICATION" in
  atmo|neople-game-analytics|ontology-asal-agent) ;;
  *)
    echo "APPLICATION must be atmo, neople-game-analytics, or ontology-asal-agent" >&2
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

file="workloads/${APPLICATION}/${WORKLOAD}/environments/${ENVIRONMENT}/kustomization.yaml"
test -f "$file" || {
  echo "Image configuration not found: $file" >&2
  exit 1
}

sed -i.bak -E "s/^([[:space:]]+newTag:).*/\\1 ${IMAGE_TAG}/" "$file"
rm -f "${file}.bak"

echo "Updated $file to image tag $IMAGE_TAG"
