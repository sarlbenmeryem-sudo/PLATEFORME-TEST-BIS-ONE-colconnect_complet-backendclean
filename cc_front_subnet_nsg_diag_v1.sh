#!/usr/bin/env bash
set -euo pipefail
RG="rg-colconnect-prod-frc"
VNET="vnet-colconnect-prod-frc"

echo "== Subnets + NSG =="
az network vnet subnet list -g "$RG" --vnet-name "$VNET" \
  --query "[].{name:name, prefix:addressPrefix, nsg:networkSecurityGroup.id}" -o table

echo ""
echo "== Front VM NICs + subnet + NSG =="
mapfile -t FRONT_VM_IDS < <(az vm list -g "$RG" --query "[?contains(name,'vmss-front-colconnect-prod')].id" -o tsv)
for VM_ID in "${FRONT_VM_IDS[@]}"; do
  echo "--- VM: $VM_ID"
  NIC_ID="$(az vm show --ids "$VM_ID" --query "networkProfile.networkInterfaces[0].id" -o tsv)"
  az network nic show --ids "$NIC_ID" --query "{nic:name, subnet:ipConfigurations[0].subnet.id, nsg:networkSecurityGroup.id, ip:ipConfigurations[0].privateIpAddress}" -o jsonc
done

echo "== Done =="
