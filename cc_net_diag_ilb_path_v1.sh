#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
ILB="ilb-api-colconnect-prod"
VMSS="vmss-api-colconnect-prod"

echo "== ILB frontend IP + subnet =="
az network lb show -g "$RG" -n "$ILB" --query "frontendIpConfigurations[0].{ip:privateIpAddress, subnet:subnet.id}" -o jsonc

echo ""
echo "== Backend NICs =="
az network lb address-pool show -g "$RG" --lb-name "$ILB" -n be-api --query "backendIPConfigurations[].id" -o tsv | nl -ba

echo ""
echo "== Resolve backend NIC names + their NSG =="
mapfile -t BACKEND_IPCONF_IDS < <(az network lb address-pool show -g "$RG" --lb-name "$ILB" -n be-api --query "backendIPConfigurations[].id" -o tsv)
for IPCONF in "${BACKEND_IPCONF_IDS[@]}"; do
  NIC_ID="${IPCONF%/ipConfigurations/*}"
  echo "---"
  echo "NIC_ID=$NIC_ID"
  az network nic show --ids "$NIC_ID" --query "{name:name, subnet:ipConfigurations[0].subnet.id, nsg:networkSecurityGroup.id, privateIP:ipConfigurations[0].privateIpAddress}" -o jsonc
done

echo ""
echo "== VMSS Flexible VMs + NIC/IP =="
az vm list -g "$RG" --query "[?virtualMachineScaleSet.id!=null && contains(virtualMachineScaleSet.id, '$VMSS')].{name:name, id:id}" -o table

echo ""
echo "== Done =="
