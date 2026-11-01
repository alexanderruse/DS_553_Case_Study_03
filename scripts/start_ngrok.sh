#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_dir"

if [[ ! -f .env ]]; then
  echo "ERROR: .env is missing." >&2
  exit 1
fi
set -a
# shellcheck disable=SC1091
source .env
set +a

command -v ngrok >/dev/null || {
  echo "ERROR: ngrok is not installed in PATH. Follow README step 10." >&2
  exit 1
}

mkdir -p logs evidence
if [[ -f .ngrok.pid ]] && kill -0 "$(cat .ngrok.pid)" 2>/dev/null; then
  echo "ERROR: ngrok already appears to be running with PID $(cat .ngrok.pid)." >&2
  exit 1
fi

ngrok http --log=stdout "http://127.0.0.1:${PUBLIC_GATEWAY_PORT}" >logs/ngrok.log 2>&1 &
ngrok_pid=$!
printf '%s\n' "$ngrok_pid" >.ngrok.pid

public_url=""
for _ in {1..30}; do
  public_url=$(python3 - <<'PY' 2>/dev/null || true
import json, urllib.request
with urllib.request.urlopen("http://127.0.0.1:4040/api/tunnels", timeout=1) as response:
    tunnels = json.load(response).get("tunnels", [])
print(next((t["public_url"] for t in tunnels if t.get("proto") == "https"), ""))
PY
)
  [[ -n "$public_url" ]] && break
  sleep 1
done

if [[ -z "$public_url" ]]; then
  echo "ERROR: ngrok did not publish a URL. Inspect logs/ngrok.log." >&2
  exit 1
fi

# Recreate only Grafana so redirects and asset URLs use the public subpath.
PUBLIC_BASE_URL="$public_url" docker compose up -d --no-deps --force-recreate grafana

cat >evidence/public_urls.txt <<EOF
Base URL: $public_url/
API product: $public_url/api/
Local product: $public_url/local/
Grafana: $public_url/grafana/
EOF

cat evidence/public_urls.txt
echo "ngrok PID: $ngrok_pid"
echo "Log: $repo_dir/logs/ngrok.log"
