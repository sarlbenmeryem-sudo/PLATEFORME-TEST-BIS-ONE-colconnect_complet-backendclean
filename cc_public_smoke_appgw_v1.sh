#!/usr/bin/env bash
set -euo pipefail
IP="${1:-20.74.38.64}"

echo "== Smoke AppGW IP=$IP =="
curl -sS -o /dev/null -w "GET / => HTTP %{http_code}\n" --max-time 8 "http://$IP/" || true
curl -sS -o /dev/null -w "GET /api/health => HTTP %{http_code}\n" --max-time 8 "http://$IP/api/health" || true
curl -sS -o /dev/null -w "GET /api/openapi.json => HTTP %{http_code}\n" --max-time 8 "http://$IP/api/openapi.json" || true
curl -sS -o /dev/null -w "GET /api/docs => HTTP %{http_code}\n" --max-time 8 "http://$IP/api/docs" || true
echo "== Done =="
echo "Rollback (git): git reset --hard HEAD~1"
