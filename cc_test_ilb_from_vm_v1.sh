#!/usr/bin/env bash
set -euo pipefail
RG="rg-colconnect-prod-frc"
VMSS="vmss-api-colconnect-prod"

# pick first VM in VMSS flexible
VM_ID="$(az vm list -g "$RG" --query "[?virtualMachineScaleSet.id!=null && contains(virtualMachineScaleSet.id, '$VMSS')].id | [0]" -o tsv)"
echo "VM_ID=$VM_ID"

ILB_IP="10.10.2.10"   # garde ton IP pour le test, on confirmera avec le diag ILB v2
PORT="8000"

az vm run-command invoke \
  --ids "$VM_ID" \
  --command-id RunShellScript \
  --scripts @- <<SCRIPT
bash -lc '
set -e
echo "== Test TCP to ILB ${ILB_IP}:${PORT} =="
nc -vz -w 3 ${ILB_IP} ${PORT} || true
echo "== Test HTTP /health via ILB =="
curl -sv --max-time 5 http://${ILB_IP}:${PORT}/health || true
'
SCRIPT
