#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_dir"

if [[ ! -f .env ]]; then
  echo "ERROR: copy .env.example to .env and fill it in first." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

failures=0
check() {
  local name=$1 url=$2
  if curl --fail --silent --show-error --max-time 10 "$url" >/dev/null; then
    printf 'PASS  %s  %s\n' "$name" "$url"
  else
    printf 'FAIL  %s  %s\n' "$name" "$url" >&2
    failures=$((failures + 1))
  fi
}

check "public gateway" "http://127.0.0.1:${PUBLIC_GATEWAY_PORT}/"
check "API product" "http://127.0.0.1:${PUBLIC_GATEWAY_PORT}/api/"
check "local product" "http://127.0.0.1:${PUBLIC_GATEWAY_PORT}/local/"
check "Prometheus" "http://127.0.0.1:${PROMETHEUS_PORT}/-/ready"
check "Grafana" "http://127.0.0.1:${GRAFANA_PORT}/api/health"

for service in api_product local_product; do
  if docker compose exec -T "$service" curl --fail --silent http://127.0.0.1:8000/metrics \
      | grep -q '^resumelens_build_info'; then
    printf 'PASS  %s Python metrics on :8000\n' "$service"
  else
    printf 'FAIL  %s Python metrics on :8000\n' "$service" >&2
    failures=$((failures + 1))
  fi
  if docker compose exec -T "$service" curl --fail --silent http://127.0.0.1:9100/metrics \
      | grep -q '^node_exporter_build_info'; then
    printf 'PASS  %s Node Exporter metrics on :9100\n' "$service"
  else
    printf 'FAIL  %s Node Exporter metrics on :9100\n' "$service" >&2
    failures=$((failures + 1))
  fi
done

if curl --fail --silent "http://127.0.0.1:${PROMETHEUS_PORT}/api/v1/query?query=up" \
    | grep -q '"value"'; then
  printf 'PASS  Prometheus query API\n'
else
  printf 'FAIL  Prometheus query API\n' >&2
  failures=$((failures + 1))
fi

if (( failures > 0 )); then
  printf '\n%d validation check(s) failed.\n' "$failures" >&2
  exit 1
fi
printf '\nAll stack validation checks passed.\n'
