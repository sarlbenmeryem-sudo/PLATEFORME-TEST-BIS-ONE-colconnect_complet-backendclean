#!/usr/bin/env bash
set -euo pipefail

IMAGE="cc-local-test:api-prefix"
CONTEXT_DIR="${1:-.}"

echo "== Build local image =="
docker build -t "$IMAGE" "$CONTEXT_DIR"

echo ""
echo "== Run temp container =="
CID="$(docker run -d -e PORT=8000 -e APP_MODULE=main:app -p 18000:8000 "$IMAGE")"
echo "CID=$CID"

cleanup() { docker rm -f "$CID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo ""
echo "== Wait + test =="
sleep 2

echo "--- /health"
curl -sS -o /dev/null -w "HTTP %{http_code}\n" --max-time 5 http://127.0.0.1:18000/health || true

echo "--- /api/health"
curl -sS -o /dev/null -w "HTTP %{http_code}\n" --max-time 5 http://127.0.0.1:18000/api/health || true

echo "--- /api/openapi.json (probe)"
curl -sS --max-time 5 http://127.0.0.1:18000/api/openapi.json | head -c 300 || true
echo ""

echo ""
echo "== Grep routes containing /api/ (from openapi) =="
curl -sS --max-time 5 http://127.0.0.1:18000/api/openapi.json | tr -d '\n' | grep -oE '"/api/[^"]+"' | head -n 20 || true

echo ""
echo "== Done =="
echo "Rollback (git): git reset --hard HEAD~1"
