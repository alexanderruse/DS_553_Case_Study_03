#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_dir"

if [[ ! -f .ngrok.pid ]]; then
  echo "No .ngrok.pid file exists."
  exit 0
fi
pid=$(cat .ngrok.pid)
if kill -0 "$pid" 2>/dev/null; then
  kill "$pid"
  echo "Stopped ngrok PID $pid."
else
  echo "ngrok PID $pid was not running."
fi
rm -f .ngrok.pid
