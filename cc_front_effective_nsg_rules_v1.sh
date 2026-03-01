#!/usr/bin/env bash
set -euo pipefail
RG="rg-colconnect-prod-frc"

VM_ID="$(az vm list -g "$RG" --query "[?contains(name,'vmss-front-colconnect-prod')].id | [0]" -o tsv)"
NIC_ID="$(az vm show --ids "$VM_ID" --query "networkProfile.networkInterfaces[0].id" -o tsv)"
echo "VM_ID=$VM_ID"
echo "NIC_ID=$NIC_ID"

echo ""
echo "== Effective NSG rules (Outbound focus) =="
az network nic list-effective-nsg --ids "$NIC_ID" -o jsonc | sed -n '1,220p'

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
