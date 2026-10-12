#!/bin/sh

q_interior_neon_host_from_env() {
  env_file=$1
  if [ ! -f "$env_file" ]; then
    echo "API environment File variable is missing" >&2
    return 1
  fi

  jdbc_url=$(awk -F= '
    $1 == "SPRING_DATASOURCE_URL" {
      count++
      sub(/^[^=]*=/, "")
      value = $0
    }
    END {
      if (count != 1) exit 1
      print value
    }
  ' "$env_file") || {
    echo "API environment File variable must contain exactly one SPRING_DATASOURCE_URL" >&2
    return 1
  }

  case "$jdbc_url" in
    jdbc:postgresql://*) authority=${jdbc_url#jdbc:postgresql://} ;;
    *)
      echo "SPRING_DATASOURCE_URL must be a PostgreSQL JDBC URL" >&2
      return 1
      ;;
  esac

  neon_host=${authority%%[:/?]*}
  if ! printf '%s' "$neon_host" | grep -Eq '^[a-z0-9.-]+\.neon\.tech$'; then
    echo "SPRING_DATASOURCE_URL must target a Neon hostname" >&2
    return 1
  fi

  printf '%s\n' "$neon_host"
}
