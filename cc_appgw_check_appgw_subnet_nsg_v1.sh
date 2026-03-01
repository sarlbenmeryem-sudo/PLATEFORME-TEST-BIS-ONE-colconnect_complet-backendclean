#!/usr/bin/env bash
set -euo pipefail
RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

SUBNET_ID="$(az network application-gateway show -g "$RG" -n "$APPGW" --query "gatewayIPConfigurations[0].subnet.id" -o tsv)"
echo "SUBNET_ID=$SUBNET_ID"
az network vnet subnet show --ids "$SUBNET_ID" --query "{name:name,prefix:addressPrefix,nsg:networkSecurityGroup.id}" -o jsonc

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
