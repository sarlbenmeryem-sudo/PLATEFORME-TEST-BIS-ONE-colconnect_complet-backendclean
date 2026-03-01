#!/usr/bin/env bash
set -euo pipefail
RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing $1" >&2; exit 1; }; }
need az
need jq

az account show -o none

echo "== AppGW summary =="
az network application-gateway show -g "$RG" -n "$APPGW" \
  --query "{name:name,sku:sku.name,gwIpConf:gatewayIpConfigurations[].subnet.id,feIpConf:frontendIPConfigurations[].subnet.id}" -o json | jq .

echo ""
echo "== Raw candidate subnet ids =="
az network application-gateway show -g "$RG" -n "$APPGW" -o json |
jq -r '[
  (.gatewayIpConfigurations[]?.subnet.id // empty),
  (.frontendIPConfigurations[]?.subnet.id // empty)
] | .[]' | nl -ba
