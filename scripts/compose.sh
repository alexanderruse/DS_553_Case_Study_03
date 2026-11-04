#!/usr/bin/env bash
# Run the installed Docker Compose implementation, preferring the modern CLI
# plugin and falling back to the legacy docker-compose binary.
set -Eeuo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/lib/compose.sh
source "$repo_dir/scripts/lib/compose.sh"
compose_detect
compose "$@"
