#!/usr/bin/env bash
set -euo pipefail
RG="rg-colconnect-prod-frc"
VNET="vnet-colconnect-prod-frc"
SUBNET="snet-api"

echo "== Subnet properties (NSG + route table) =="
az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n "$SUBNET" \
  --query "{id:id, addressPrefix:addressPrefix, nsg:networkSecurityGroup.id, routeTable:routeTable.id}" -o jsonc

echo ""
echo "== Effective routes on VM NICs (Flexible VMSS) =="
mapfile -t VM_IDS < <(az vm list -g "$RG" --query "[?virtualMachineScaleSet.id!=null].id" -o tsv)
for VM_ID in "${VM_IDS[@]}"; do
  echo "--- VM: $VM_ID"
  NIC_ID="$(az vm show --ids "$VM_ID" --query "networkProfile.networkInterfaces[0].id" -o tsv)"
  echo "NIC_ID=$NIC_ID"
  az network nic show-effective-route-table --ids "$NIC_ID" -o table | head -n 40 || true
done

echo ""
echo "== Done =="
