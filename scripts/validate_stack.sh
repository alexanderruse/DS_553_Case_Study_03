#!/usr/bin/env bash
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

check "public gateway" "http://127.0.0.1:${PUBLIC_GATEWAY_PORT:-2100}/"
check "API product" "http://127.0.0.1:${PUBLIC_GATEWAY_PORT:-2100}/api/"
check "local product" "http://127.0.0.1:${PUBLIC_GATEWAY_PORT:-2100}/local/"
check "Prometheus" "http://127.0.0.1:${PROMETHEUS_PORT:-2103}/-/ready"
check "Grafana" "http://127.0.0.1:${GRAFANA_PORT:-2104}/grafana/api/health"

for service in api_product local_product; do
  if compose exec -T "$service" curl --fail --silent http://127.0.0.1:8000/metrics \
      | grep '^resumelens_build_info' >/dev/null; then
    printf 'PASS  %s Python metrics on :8000\n' "$service"
  else
    printf 'FAIL  %s Python metrics on :8000\n' "$service" >&2
    failures=$((failures + 1))
  fi
  if compose exec -T "$service" curl --fail --silent http://127.0.0.1:9100/metrics \
      | grep '^node_exporter_build_info' >/dev/null; then
    printf 'PASS  %s Node Exporter metrics on :9100\n' "$service"
  else
    printf 'FAIL  %s Node Exporter metrics on :9100\n' "$service" >&2
    failures=$((failures + 1))
  fi
done

if curl --fail --silent "http://127.0.0.1:${PROMETHEUS_PORT:-2103}/api/v1/query?query=up" \
    | grep '"value"' >/dev/null; then
  printf 'PASS  Prometheus query API\n'
else
  printf 'FAIL  Prometheus query API\n' >&2
  failures=$((failures + 1))
fi

if [[ -n "${NGROK_AUTHTOKEN:-}" ]]; then
  public_url=$(curl --fail --silent "http://127.0.0.1:${NGROK_API_PORT:-2109}/api/tunnels" \
    | python3 -c 'import json,sys; t=json.load(sys.stdin).get("tunnels",[]); print(next((x["public_url"] for x in t if x["public_url"].startswith("https://")), ""))' \
    2>/dev/null || true)
  if [[ -z "$public_url" ]]; then
    public_url=$(compose logs --no-color ngrok 2>&1 \
      | grep -oE 'url=https://[^ ]+' \
      | tail -n 1 \
      | cut -d= -f2- || true)
  fi
  if [[ -z "$public_url" ]]; then
    printf 'FAIL  ngrok tunnel is not published\n' >&2
    failures=$((failures + 1))
  elif curl --fail --silent --show-error --max-time 20 \
      --header 'ngrok-skip-browser-warning: true' "$public_url/grafana/" >/dev/null; then
    printf 'PASS  ngrok tunnel and public Grafana  %s/grafana/\n' "$public_url"
  else
    printf 'FAIL  ngrok is published but public Grafana is unavailable  %s/grafana/\n' "$public_url" >&2
    failures=$((failures + 1))
  fi
fi

if (( failures > 0 )); then
  printf '\n%d validation check(s) failed.\n' "$failures" >&2
  exit 1
fi
printf '\nAll stack validation checks passed.\n'
