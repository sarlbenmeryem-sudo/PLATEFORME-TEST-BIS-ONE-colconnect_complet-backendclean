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
set -euo pipefail

echo "== docker ps =="
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}" || true
echo ""

CID="$(docker ps --format "{{.ID}}\t{{.Ports}}" | awk -F"\t" "$2 ~ /0\\.0\\.0\\.0:8000->/ {print $1; exit}")"
if [[ -z "${CID:-}" ]]; then
  # fallback: premier container running
  CID="$(docker ps --format "{{.ID}}" | head -n 1 || true)"
fi

echo "CID=$CID"
if [[ -z "${CID:-}" ]]; then
  echo "❌ No running container found"
  exit 0
fi

echo ""
echo "== curl from VM (host) to localhost:8000 =="
curl -sv --max-time 5 http://127.0.0.1:8000/health || true
curl -sv --max-time 5 http://127.0.0.1:8000/api/health || true
curl -sv --max-time 5 http://127.0.0.1:8000/api/openapi.json || true
curl -sv --max-time 5 http://127.0.0.1:8000/api/docs || true

echo ""
echo "== curl from inside container =="
docker exec "$CID" sh -lc "curl -sv --max-time 5 http://127.0.0.1:8000/health || true"
docker exec "$CID" sh -lc "curl -sv --max-time 5 http://127.0.0.1:8000/api/health || true"
docker exec "$CID" sh -lc "curl -sv --max-time 5 http://127.0.0.1:8000/api/openapi.json || true"
docker exec "$CID" sh -lc "curl -sv --max-time 5 http://127.0.0.1:8000/api/docs || true"

echo ""
echo "== last logs (80 lines) =="
docker logs --tail 80 "$CID" || true
'
SCRIPT
done

echo "== Done =="
echo "Rollback (git): git reset --hard HEAD~1"
