#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
VMSS="vmss-api-colconnect-prod"

mapfile -t VM_IDS < <(az vm list -g "$RG" --query "[?virtualMachineScaleSet.id!=null && contains(virtualMachineScaleSet.id, '$VMSS')].id" -o tsv)
if (( ${#VM_IDS[@]} == 0 )); then
  echo "❌ No VMs found for VMSS=$VMSS" >&2
  exit 1
fi

for VM_ID in "${VM_IDS[@]}"; do
  echo "=============================="
  echo "== VM: $VM_ID =="
  az vm run-command invoke \
    --ids "$VM_ID" \
    --command-id RunShellScript \
    --scripts @- <<'SCRIPT'
bash -lc '
set -e

echo "== docker ps =="
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | sed -n "1,10p" || true

echo "== docker inspect (health/exit) =="
docker inspect colconnect-api --format "State={{json .State}}  Config={{json .Config.Cmd}}" 2>/dev/null || echo "no container colconnect-api"

echo "== last logs (120 lines) =="
docker logs --tail=120 colconnect-api 2>&1 || true

echo "== curl local /health (verbose) =="
curl -v --max-time 5 http://127.0.0.1:8000/health 2>&1 | tail -n 40 || true

echo "== curl root (verbose) =="
curl -v --max-time 5 http://127.0.0.1:8000/ 2>&1 | tail -n 40 || true

echo "== test import inside container (main:app) =="
docker exec colconnect-api sh -lc "python - <<PY
import importlib,sys
m = importlib.import_module('main')
print('main module OK:', m)
print('has app:', hasattr(m,'app'))
PY" 2>&1 || true

echo "== list top-level py files =="
docker exec colconnect-api sh -lc "ls -la /app | head -n 50" 2>&1 || true
'
SCRIPT
done

echo "== Done =="
