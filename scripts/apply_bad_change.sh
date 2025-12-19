#!/usr/bin/env bash
set -euo pipefail

echo "Applying bad change: VERSION=v1.4, CHANGE_ID=MENU-211 (simulated regression in east)"
docker compose stop kitchen-api >/dev/null

OWNER="kitchen-team" VERSION="v1.4" CHANGE_ID="MENU-211" docker compose up -d --build kitchen-api

echo "Emitting change event..."
curl -sS -X POST http://localhost:5101/change \
  -H "Content-Type: application/json" \
  -d '{"change_id":"MENU-211","version":"v1.4","owner":"kitchen-team","description":"Promo algorithm updated; east region regression"}'
echo
echo "Done."
