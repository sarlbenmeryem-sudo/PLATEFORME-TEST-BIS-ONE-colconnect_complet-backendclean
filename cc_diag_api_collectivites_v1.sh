#!/usr/bin/env bash
set -euo pipefail

BASE="https://api.colconnect.fr"

echo "== Search =="
curl -sS -D /tmp/h1 "$BASE/api/collectivites/search?q=paris&limit=10" -o /tmp/b1 || true
head -n 1 /tmp/h1 || true
echo "Body:"
head -c 600 /tmp/b1; echo

echo ""
echo "== By ID (replace ID) =="
ID="${1:-}"
if [[ -z "$ID" ]]; then
  echo "ℹ️ Provide an id: bash cc_diag_api_collectivites_v1.sh <ID>"
  exit 0
fi
curl -sS -D /tmp/h2 "$BASE/api/collectivites/$ID" -o /tmp/b2 || true
head -n 1 /tmp/h2 || true
echo "Body:"
head -c 600 /tmp/b2; echo
