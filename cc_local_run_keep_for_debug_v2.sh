#!/usr/bin/env bash
set -euo pipefail

CONTEXT_DIR="${1:-.}"
IMAGE="cc-local-test:api-prefix"
NAME="cc_api_prefix_debug"
HOST_PORT="18000"
CONT_PORT="8000"

echo "== Build local image =="
docker build -t "$IMAGE" "$CONTEXT_DIR"

echo ""
echo "== Stop old debug container if exists =="
docker rm -f "$NAME" >/dev/null 2>&1 || true

echo ""
echo "== Run container (kept) on ${HOST_PORT}->${CONT_PORT} =="
CID="$(docker run -d --name "$NAME" -e PORT="$CONT_PORT" -e APP_MODULE=main:app -p "${HOST_PORT}:${CONT_PORT}" "$IMAGE")"
echo "CID=$CID"

echo ""
echo "== Wait readiness (max 30s) =="
for i in $(seq 1 30); do
  code="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 2 "http://127.0.0.1:${HOST_PORT}/health" || true)"
  if [[ "$code" == "200" ]]; then
    echo "✅ Ready: /health HTTP 200"
    break
  fi
  sleep 1
  if [[ "$i" == "30" ]]; then
    echo "❌ Not ready after 30s"
  fi
done

echo ""
echo "== Tests =="
curl -sS -o /dev/null -w "/health => HTTP %{http_code}\n" --max-time 5 "http://127.0.0.1:${HOST_PORT}/health" || true
curl -sS -o /dev/null -w "/api/health => HTTP %{http_code}\n" --max-time 5 "http://127.0.0.1:${HOST_PORT}/api/health" || true
curl -sS -o /dev/null -w "/api/docs => HTTP %{http_code}\n" --max-time 5 "http://127.0.0.1:${HOST_PORT}/api/docs" || true

echo ""
echo "== Logs (last 60 lines) =="
docker logs "$NAME" 2>&1 | tail -n 60 || true

echo ""
echo "== Keep container for debug =="
echo "docker logs -f $NAME"
echo "docker exec -it $NAME sh"
echo "docker rm -f $NAME"

echo "Rollback (git): git reset --hard HEAD~1"
