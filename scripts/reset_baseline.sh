#!/usr/bin/env bash
set -euo pipefail

echo "Resetting to baseline: VERSION=v1.3, CHANGE_ID=MENU-200"
docker compose stop kitchen-api >/dev/null

OWNER="platform" VERSION="v1.3" CHANGE_ID="MENU-200" docker compose up -d --build kitchen-api

echo "Emitting baseline change event..."
curl -sS -X POST http://localhost:5101/change \
  -H "Content-Type: application/json" \
  -d '{"change_id":"MENU-200","version":"v1.3","owner":"platform","description":"Baseline stable build"}'
echo
echo "Done."
