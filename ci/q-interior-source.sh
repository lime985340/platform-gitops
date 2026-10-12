#!/bin/sh
set -eu
test "${CI_DEBUG_TRACE:-false}" != true || { echo 'Debug trace must be disabled' >&2; exit 1; }
test "${CI_PIPELINE_SOURCE:-}" = pipeline || { echo 'Q Interior deployment must come from a multi-project source pipeline' >&2; exit 1; }
case "$Q_SOURCE_SHA" in ''|*[!a-f0-9]*) echo 'Invalid source SHA' >&2; exit 1 ;; esac
test "${#Q_SOURCE_SHA}" -eq 40
case "$Q_ACTION" in
  deploy-api) source_name=q-interior-api ;;
  deploy-web) source_name=q-interior-client ;;
  *) exit 1 ;;
esac
case "$Q_ENVIRONMENT" in
  dev) test "$Q_SOURCE_REF" = main ;;
  prod) printf '%s' "$Q_SOURCE_REF" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' ;;
  *) exit 1 ;;
esac

# The upstream protected-branch/tag pipeline builds and pushes this exact SHA
# before triggering GitOps. The deploy job only consumes that immutable image
# tag, so cloning the private source repository here is unnecessary and would
# require granting platform-gitops read access to q-interior-client.
printf 'Validated %s source identity %s@%s for %s deployment\n' \
  "$source_name" "$Q_SOURCE_REF" "$Q_SOURCE_SHA" "$Q_ENVIRONMENT"
