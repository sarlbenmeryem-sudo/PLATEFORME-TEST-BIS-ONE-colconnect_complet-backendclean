#!/usr/bin/env bash
set -euo pipefail

CID="${1:-}"
if [[ -z "${CID:-}" ]]; then
  echo "Usage: $0 <CONTAINER_ID_OR_NAME>" >&2
  echo "Tip: docker ps --format 'table {{.ID}}\t{{.Image}}\t{{.Names}}'" >&2
  exit 2
fi

echo "== docker ps (match) =="
docker ps --no-trunc --filter "id=$CID" || true
docker ps --no-trunc --filter "name=$CID" || true

echo ""
echo "== docker inspect (cmd/entrypoint/env/ports/state) =="
docker inspect "$CID" --format $'Name={{.Name}}\nImage={{.Config.Image}}\nEntrypoint={{json .Config.Entrypoint}}\nCmd={{json .Config.Cmd}}\nExposedPorts={{json .Config.ExposedPorts}}\nPortBindings={{json .HostConfig.PortBindings}}\nEnv={{json .Config.Env}}\nState={{json .State}}' || true

echo ""
echo "== Processes (inside container) =="
docker exec "$CID" sh -lc 'ps auxww || true'

echo ""
echo "== Listening sockets (inside container) =="
docker exec "$CID" sh -lc 'command -v ss >/dev/null 2>&1 && ss -ltnp || (command -v netstat >/dev/null 2>&1 && netstat -ltnp) || echo "no ss/netstat"' || true

echo ""
echo "== Test curl inside container (localhost:8000) =="
docker exec "$CID" sh -lc 'command -v curl >/dev/null 2>&1 || (apt-get update >/dev/null 2>&1 && apt-get install -y curl >/dev/null 2>&1) || true; curl -sv --max-time 5 http://127.0.0.1:8000/health || true; echo ""; curl -sv --max-time 5 http://127.0.0.1:8000/api/health || true' || true

echo ""
echo "== Container logs (last 200) =="
docker logs --tail 200 "$CID" 2>&1 || true

echo ""
echo "== Done =="
echo "Rollback (git): git reset --hard HEAD~1"
