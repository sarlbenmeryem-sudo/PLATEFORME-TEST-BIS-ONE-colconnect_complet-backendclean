#!/usr/bin/env bash
set -euo pipefail
RG="rg-colconnect-prod-frc"
ILB="ilb-api-colconnect-prod"

echo "== LB raw (first 200 lines) =="
az network lb show -g "$RG" -n "$ILB" -o jsonc | sed -n '1,200p'

echo ""
echo "== Frontend config count =="
az network lb show -g "$RG" -n "$ILB" --query "length(frontendIpConfigurations)" -o tsv

echo ""
echo "== Frontend names =="
az network lb show -g "$RG" -n "$ILB" --query "frontendIpConfigurations[].name" -o tsv

echo "== Done =="
