#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
VMSS="vmss-api-colconnect-prod"

IMAGE="acrcolconnectprodfrc.azurecr.io/colconnect-api:prod"
NAME="colconnect-api"
PORT="8000"
APP_MODULE="main:app"

mapfile -t VM_IDS < <(az vm list -g "$RG" --query "[?virtualMachineScaleSet.id!=null && contains(virtualMachineScaleSet.id, '$VMSS')].id" -o tsv)
if (( ${#VM_IDS[@]} == 0 )); then
  echo "❌ No VMs found for VMSS=$VMSS" >&2
  exit 1
fi

for VM_ID in "${VM_IDS[@]}"; do
  echo "=============================="
  echo "== Rolling VM: $VM_ID =="

  az vm run-command invoke \
    --ids "$VM_ID" \
    --command-id RunShellScript \
    --scripts @- <<SCRIPT
bash -lc '
set -euo pipefail

echo "== Pull image =="
docker pull "$IMAGE"

echo ""
echo "== Stop/remove existing container (if any) =="
docker rm -f "$NAME" >/dev/null 2>&1 || true

echo ""
echo "== Run new container =="
docker run -d --restart unless-stopped --name "$NAME" \
  -p ${PORT}:${PORT} \
  -e PORT=${PORT} \
  -e APP_MODULE=${APP_MODULE} \
  "$IMAGE"

echo ""
echo "== Smoke =="
sleep 2
curl -sS -o /dev/null -w "GET /health => HTTP %{http_code}\n" --max-time 5 http://127.0.0.1:${PORT}/health || true
curl -sS -o /dev/null -w "GET /api/health => HTTP %{http_code}\n" --max-time 5 http://127.0.0.1:${PORT}/api/health || true

echo ""
echo "== logs (20 lines) =="
docker logs --tail 20 "$NAME" || true
'
SCRIPT

done

echo "== Done =="
echo "Rollback (git): git reset --hard HEAD~1"
