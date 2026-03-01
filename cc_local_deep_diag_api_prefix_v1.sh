#!/usr/bin/env bash
set -euo pipefail

CID="${1:-cc_api_prefix_debug}"
echo "== CID=$CID =="

echo ""
echo "== 1) docker inspect (State + user) =="
docker inspect "$CID" --format $'Name={{.Name}}\nStatus={{.State.Status}} Running={{.State.Running}} ExitCode={{.State.ExitCode}} Error={{.State.Error}}\nUser={{.Config.User}}\nImage={{.Config.Image}}\nCmd={{json .Config.Cmd}}\nEntrypoint={{json .Config.Entrypoint}}' || true

echo ""
echo "== 2) /proc/1 cmdline + env (inside, as root) =="
docker exec -u 0 "$CID" sh -lc '
set -e
echo "-- /proc/1/cmdline --"
tr "\0" " " < /proc/1/cmdline || true
echo ""
echo "-- /proc/1/environ (filtered) --"
tr "\0" "\n" < /proc/1/environ | egrep "^(PORT|APP_MODULE|WORKERS|PATH)=" || true
' || true

echo ""
echo "== 3) Check binaries (python/gunicorn/uvicorn) (as root) =="
docker exec -u 0 "$CID" sh -lc '
set -e
command -v python || true
python -V || true
command -v gunicorn || true
command -v uvicorn || true
python -c "import gunicorn, uvicorn; print(\"imports: gunicorn+uvicorn OK\")" || true
' || true

echo ""
echo "== 4) Does main:app import? (as root) =="
docker exec -u 0 "$CID" sh -lc '
set -e
python - <<PY
import os, importlib, traceback
print("PORT=", os.getenv("PORT"))
print("APP_MODULE=", os.getenv("APP_MODULE"))
try:
    m = importlib.import_module("main")
    print("main imported OK:", m)
    app = getattr(m, "app", None)
    print("main.app =", app)
except Exception as e:
    print("IMPORT main FAILED:", repr(e))
    traceback.print_exc()
PY
' || true

echo ""
echo "== 5) Listening ports via /proc/net/tcp (as root) =="
docker exec -u 0 "$CID" sh -lc '
set -e
python - <<PY
import socket
def parse(path):
    out=[]
    with open(path,"r") as f:
        next(f)
        for line in f:
            cols=line.split()
            local=cols[1]
            state=cols[3]
            if state!="0A":  # LISTEN
                continue
            ip_hex, port_hex = local.split(":")
            port=int(port_hex,16)
            out.append(port)
    return sorted(set(out))
ports=parse("/proc/net/tcp")
ports6=parse("/proc/net/tcp6") if __import__("os").path.exists("/proc/net/tcp6") else []
ports6=sorted(set(ports6))
print("LISTEN tcp ports:", ports)
print("LISTEN tcp6 ports:", ports6)
PY
' || true

echo ""
echo "== 6) Quick curl from inside (as root) =="
docker exec -u 0 "$CID" sh -lc '
set -e
if ! command -v curl >/dev/null 2>&1; then
  apt-get update >/dev/null 2>&1 || true
  apt-get install -y curl >/dev/null 2>&1 || true
fi
echo "-- curl localhost:8000/health --"
curl -sv --max-time 3 http://127.0.0.1:8000/health || true
echo ""
echo "-- curl localhost:8000/api/health --"
curl -sv --max-time 3 http://127.0.0.1:8000/api/health || true
' || true

echo ""
echo "== 7) Logs (last 200) =="
docker logs --tail 200 "$CID" 2>&1 || true

echo ""
echo "== Done =="
echo "Rollback (git): git reset --hard HEAD~1"
