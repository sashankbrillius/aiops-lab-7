#!/usr/bin/env bash
set -euo pipefail

HOST="${HOST:-http://localhost:5101}"

echo "Generating traffic to $HOST/order (east + west)..."
for i in {1..40}; do
  curl -sS "$HOST/order?region=east" > /dev/null
  curl -sS "$HOST/order?region=west" > /dev/null
done
echo "Done."
