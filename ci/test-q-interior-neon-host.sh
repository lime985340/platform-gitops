#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$script_dir/q-interior-neon-host.sh"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

cat > "$tmp_dir/dev.env" <<'ENV'
SPRING_DATASOURCE_URL=jdbc:postgresql://dev-pooler.c-13.us-east-1.aws.neon.tech:5432/neondb?sslmode=require
SPRING_DATASOURCE_USERNAME=neondb_owner
SPRING_DATASOURCE_PASSWORD=not-printed
ENV
host=$(q_interior_neon_host_from_env "$tmp_dir/dev.env")
[ "$host" = 'dev-pooler.c-13.us-east-1.aws.neon.tech' ]

cat > "$tmp_dir/prod.env" <<'ENV'
SPRING_DATASOURCE_URL=jdbc:postgresql://prod-pooler.c-13.us-east-1.aws.neon.tech:5432/neondb?sslmode=require
ENV
host=$(q_interior_neon_host_from_env "$tmp_dir/prod.env")
[ "$host" = 'prod-pooler.c-13.us-east-1.aws.neon.tech' ]

cat > "$tmp_dir/invalid.env" <<'ENV'
SPRING_DATASOURCE_URL=jdbc:postgresql://db.example.com:5432/neondb
ENV
if q_interior_neon_host_from_env "$tmp_dir/invalid.env" >/dev/null 2>&1; then
  echo 'A non-Neon hostname was accepted' >&2
  exit 1
fi

cat > "$tmp_dir/duplicate.env" <<'ENV'
SPRING_DATASOURCE_URL=jdbc:postgresql://dev-pooler.c-13.us-east-1.aws.neon.tech:5432/neondb
SPRING_DATASOURCE_URL=jdbc:postgresql://other-pooler.c-13.us-east-1.aws.neon.tech:5432/neondb
ENV
if q_interior_neon_host_from_env "$tmp_dir/duplicate.env" >/dev/null 2>&1; then
  echo 'Duplicate datasource URLs were accepted' >&2
  exit 1
fi

echo 'Q Interior Neon host extraction: PASS'
