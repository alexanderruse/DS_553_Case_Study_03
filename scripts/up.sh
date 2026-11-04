#!/usr/bin/env bash
# Build and start the stack. If NGROK_AUTHTOKEN is set in .env, wait for the
# public tunnel, point Grafana at it, and record the public URLs.
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_dir"
# shellcheck source=scripts/lib/compose.sh
source "$repo_dir/scripts/lib/compose.sh"

if [[ ! -f .env ]]; then
  echo "ERROR: copy .env.example to .env and fill it in first." >&2
  exit 1
fi
set -a
# shellcheck disable=SC1091
source .env
set +a
compose_detect
echo "Using $COMPOSE_VERSION_OUTPUT"

gateway_port=${PUBLIC_GATEWAY_PORT:-2100}
if [[ -n "${NGROK_AUTHTOKEN:-}" && -n "${NGROK_DOMAIN:-}" ]]; then
  export PUBLIC_BASE_URL="https://${NGROK_DOMAIN}"
fi

# Compose 1.29 cannot reliably recreate containers created from BuildKit/OCI
# images on current Docker Engines because the legacy ContainerConfig image
# field no longer exists. Avoid that broken recreation path by removing only
# this Compose project's old containers before rebuilding. Named volumes are
# preserved unless LEGACY_COMPOSE_RESET_VOLUMES=true is explicitly configured.
if [[ "$COMPOSE_IS_LEGACY" == "true" ]]; then
  echo "Legacy Compose detected; removing this project's old containers before rebuilding."
  down_args=(down --remove-orphans)
  if [[ "${LEGACY_COMPOSE_RESET_VOLUMES:-false}" == "true" ]]; then
    echo "LEGACY_COMPOSE_RESET_VOLUMES=true; named project volumes will also be removed."
    down_args+=(--volumes)
  fi
  compose "${down_args[@]}" || true

  # A failed Compose v1 recreation can leave renamed containers behind. Remove
  # only containers carrying this exact project's Compose label.
  if [[ -n "${COMPOSE_PROJECT_NAME:-}" ]]; then
    while IFS= read -r container_id; do
      [[ -z "$container_id" ]] || docker rm -f "$container_id"
    done < <(docker ps -aq \
      --filter "label=com.docker.compose.project=${COMPOSE_PROJECT_NAME}")
  fi
fi

compose up -d --build
mkdir -p evidence

if [[ -z "${NGROK_AUTHTOKEN:-}" ]]; then
  host=$(hostname -I 2>/dev/null | awk '{print $1}')
  echo
  echo "ngrok disabled (NGROK_AUTHTOKEN is blank). Stack is available on the VM ports:"
  echo "  Gateway:    http://${host:-localhost}:${gateway_port}/"
  echo "  API:        http://${host:-localhost}:${gateway_port}/api/"
  echo "  Local:      http://${host:-localhost}:${gateway_port}/local/"
  echo "  Grafana:    http://${host:-localhost}:${gateway_port}/grafana/"
  echo "  Prometheus: http://${host:-localhost}:${PROMETHEUS_PORT:-2103}/"
  exit 0
fi

public_url=""
for _ in {1..30}; do
  public_url=$(curl --silent --max-time 2 "http://127.0.0.1:${NGROK_API_PORT:-2109}/api/tunnels" \
    | python3 -c 'import json,sys; t=json.load(sys.stdin).get("tunnels",[]); print(next((x["public_url"] for x in t if x["public_url"].startswith("https://")), ""))' \
    2>/dev/null || true)
  # ngrok may bind its inspector to loopback inside the container. The public
  # tunnel is still healthy, so recover the URL from the startup log.
  if [[ -z "$public_url" ]]; then
    public_url=$(compose logs --no-color ngrok 2>&1 \
      | grep -oE 'url=https://[^ ]+' \
      | tail -n 1 \
      | cut -d= -f2- || true)
  fi
  [[ -n "$public_url" ]] && break
  sleep 2
done

if [[ -z "$public_url" ]]; then
  echo "ERROR: ngrok did not publish a URL. Inspect: scripts/compose.sh logs ngrok" >&2
  exit 1
fi

if [[ "${PUBLIC_BASE_URL:-}" != "$public_url" ]]; then
  # Recreate only Grafana so redirects and asset URLs use the public address.
  export PUBLIC_BASE_URL="$public_url"
  if [[ "$COMPOSE_IS_LEGACY" == "true" ]]; then
    # Compose 1.29 also fails when force-recreating this single service. Remove
    # only this project's Grafana container, then create it from scratch.
    compose stop grafana || true
    while IFS= read -r container_id; do
      [[ -z "$container_id" ]] || docker rm -f "$container_id"
    done < <(docker ps -aq \
      --filter "label=com.docker.compose.project=${COMPOSE_PROJECT_NAME}" \
      --filter "label=com.docker.compose.service=grafana")
    compose up -d --no-deps grafana
  else
    compose up -d --no-deps --force-recreate grafana
  fi
  # nginx resolves upstream service names at startup. Grafana recreation may
  # change its IP, so restart the gateway to avoid a stale-upstream 502.
  compose restart gateway
fi

cat >evidence/public_urls.txt <<URLS
Base URL: $public_url/
API product: $public_url/api/
Local product: $public_url/local/
Grafana: $public_url/grafana/
URLS
echo
cat evidence/public_urls.txt
