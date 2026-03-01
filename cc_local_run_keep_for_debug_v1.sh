#!/usr/bin/env bash
set -euo pipefail

IMAGE="cc-local-test:api-prefix"
CONTEXT_DIR="${1:-.}"
HOST_PORT="${2:-18000}"

echo "== Build local image =="
docker build -t "$IMAGE" "$CONTEXT_DIR"

echo ""
echo "== Stop old debug container if exists =="
docker rm -f cc_api_prefix_debug >/dev/null 2>&1 || true

echo ""
echo "== Run container (kept) on ${HOST_PORT}->8000 =="
CID="$(docker run -d --name cc_api_prefix_debug -e PORT=8000 -e APP_MODULE=main:app -p "${HOST_PORT}:8000" "$IMAGE")"
echo "CID=$CID"

echo ""
echo "== Quick host test =="
curl -sv --max-time 5 "http://127.0.0.1:${HOST_PORT}/health" || true
curl -sv --max-time 5 "http://127.0.0.1:${HOST_PORT}/api/health" || true

echo ""
echo "== Now run deep diag =="
./cc_local_diag_container_runtime_v2.sh "$CID"

echo ""
echo "== To cleanup later =="
echo "docker rm -f cc_api_prefix_debug"
echo "Rollback (git): git reset --hard HEAD~1"
