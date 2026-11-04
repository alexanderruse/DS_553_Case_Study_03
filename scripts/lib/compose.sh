#!/usr/bin/env bash
# Shared Docker Compose detection for modern `docker compose` and legacy
# `docker-compose` installations.

compose_detect() {
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_COMMAND=(docker compose)
  elif command -v docker-compose >/dev/null 2>&1 \
      && docker-compose version >/dev/null 2>&1; then
    COMPOSE_COMMAND=(docker-compose)
  else
    echo "ERROR: neither 'docker compose' nor 'docker-compose' is available." >&2
    return 1
  fi

  COMPOSE_VERSION_OUTPUT=$("${COMPOSE_COMMAND[@]}" version 2>&1)
  COMPOSE_IS_LEGACY=false
  if [[ "$COMPOSE_VERSION_OUTPUT" =~ [Vv]ersion[[:space:]]1\. ]]; then
    COMPOSE_IS_LEGACY=true
  fi
}

compose() {
  "${COMPOSE_COMMAND[@]}" "$@"
}
