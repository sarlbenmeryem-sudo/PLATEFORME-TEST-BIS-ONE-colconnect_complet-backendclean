#!/usr/bin/env bash
set -euo pipefail
RG="rg-colconnect-prod-frc"
ILB="ilb-api-colconnect-prod"

echo "== Frontend config count =="
az network lb show -g "$RG" -n "$ILB" --query "length(frontendIPConfigurations)" -o tsv

echo ""
echo "== Frontend names =="
az network lb show -g "$RG" -n "$ILB" --query "frontendIPConfigurations[].name" -o tsv

echo ""
echo "== Frontend IP + subnet =="
az network lb show -g "$RG" -n "$ILB" --query "frontendIPConfigurations[0].{name:name, ip:privateIPAddress, subnet:subnet.id}" -o jsonc

echo "== Done =="
echo "Rollback (git): git reset --hard HEAD~1"
