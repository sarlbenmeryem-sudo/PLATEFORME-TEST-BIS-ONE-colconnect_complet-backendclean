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
echo "== Inspect startup (first 80 log lines) =="
sleep 1
docker logs "$CID" 2>&1 | sed -n '1,80p' || true

echo ""
echo "== Container state =="
docker inspect "$CID" --format 'Status={{.State.Status}} Running={{.State.Running}} ExitCode={{.State.ExitCode}} Error={{.State.Error}}' || true

echo ""
echo "== Wait + test =="
sleep 2

echo "--- /health"
curl -sv -o /dev/null -w "HTTP %{http_code}\n" --max-time 5 http://127.0.0.1:18000/health || true

echo "--- /api/health"
curl -sv -o /dev/null -w "HTTP %{http_code}\n" --max-time 5 http://127.0.0.1:18000/api/health || true

echo "--- /api/openapi.json (probe)"
curl -sv --max-time 5 http://127.0.0.1:18000/api/openapi.json | head -c 300 || true
echo ""

echo ""
echo "== Tail logs (last 120 lines) =="
docker logs "$CID" 2>&1 | tail -n 120 || true

echo ""
echo "== Done =="
echo "Rollback (git): git reset --hard HEAD~1"
