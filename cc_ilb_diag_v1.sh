#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
ILB="ilb-api-colconnect-prod"

echo "== LB summary =="
az network lb show -g "$RG" -n "$ILB" --query "{name:name, sku:sku.name, location:location, fe:frontendIpConfigurations[].privateIpAddress}" -o jsonc

echo "== LB rules =="
az network lb rule list -g "$RG" --lb-name "$ILB" -o table

echo "== LB probes =="
az network lb probe list -g "$RG" --lb-name "$ILB" -o table

echo "== Backend pools =="
az network lb address-pool list -g "$RG" --lb-name "$ILB" --query "[].{name:name, backendIPConfigurations:backendIPConfigurations[].id}" -o jsonc

echo "== Done =="
