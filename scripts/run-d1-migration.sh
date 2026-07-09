#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
  echo "CLOUDFLARE_API_TOKEN is not set."
  echo "Create a token (D1 edit permissions), then export it:"
  echo "  export CLOUDFLARE_API_TOKEN='***'"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SQL_FILE="$ROOT_DIR/update_hvs_creator_assets.sql"

npx wrangler d1 execute gabriel_db --file="$SQL_FILE" --remote
