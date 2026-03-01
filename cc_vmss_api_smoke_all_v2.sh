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

CID="$(docker ps --format "{{.ID}}\t{{.Ports}}" \
  | grep -E "0\.0\.0\.0:8000->8000/tcp" \
  | head -n 1 | cut -f1 || true)"

if [[ -z "${CID:-}" ]]; then
  CID="$(docker ps --format "{{.ID}}" | head -n 1 || true)"
fi

echo "CID=$CID"
if [[ -z "${CID:-}" ]]; then
  echo "❌ No running container found"
  exit 0
fi

echo ""
echo "== Host curl (localhost:8000) =="
for p in /health /api/health /api/openapi.json /api/docs; do
  echo "--- GET $p"
  curl -sS -o /dev/null -w "HTTP %{http_code}\n" --max-time 5 "http://127.0.0.1:8000$p" || true
done

echo ""
echo "== Container curl (localhost:8000) =="
for p in /health /api/health /api/openapi.json /api/docs; do
  echo "--- GET $p"
  docker exec "$CID" sh -lc "curl -sS -o /dev/null -w 'HTTP %{http_code}\n' --max-time 5 http://127.0.0.1:8000$p || true"
done

echo ""
echo "== last logs (60 lines) =="
docker logs --tail 60 "$CID" || true
'
SCRIPT
done

echo "== Done =="
echo "Rollback (git): git reset --hard HEAD~1"
