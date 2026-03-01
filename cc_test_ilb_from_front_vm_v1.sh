#!/usr/bin/env bash
set -euo pipefail
RG="rg-colconnect-prod-frc"

# première VM front
VM_ID="$(az vm list -g "$RG" --query "[?contains(name,'vmss-front-colconnect-prod')].id | [0]" -o tsv)"
echo "VM_ID=$VM_ID"

ILB_IP="10.10.2.10"
PORT="8000"

az vm run-command invoke \
  --ids "$VM_ID" \
  --command-id RunShellScript \
  --scripts @- <<SCRIPT
bash -lc '
set -e
echo "== TCP test to ILB ${ILB_IP}:${PORT} =="
nc -vz -w 3 ${ILB_IP} ${PORT} || true
echo "== HTTP /health via ILB =="
curl -sv --max-time 5 http://${ILB_IP}:${PORT}/health || true
'
SCRIPT

echo "Rollback (git): git reset --hard HEAD~1"
