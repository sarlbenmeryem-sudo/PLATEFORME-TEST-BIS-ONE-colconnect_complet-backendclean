#!/usr/bin/env bash
set -euo pipefail
RG="rg-colconnect-prod-frc"
ILB="ilb-api-colconnect-prod"

echo "== Frontend IP configurations (raw) =="
az network lb show -g "$RG" -n "$ILB" --query "frontendIpConfigurations" -o jsonc

echo ""
echo "== Extract private IP + subnet (try multiple fields) =="
az network lb show -g "$RG" -n "$ILB" --query "frontendIpConfigurations[0].{name:name, privateIpAddress:privateIpAddress, privateIPAddress:privateIPAddress, subnet:subnet.id}" -o jsonc

echo ""
echo "== Done =="
