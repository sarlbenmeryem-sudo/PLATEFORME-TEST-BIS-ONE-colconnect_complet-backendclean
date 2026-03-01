#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
VNET="vnet-colconnect-prod-frc"

APPGW_SUBNET_CIDR="10.10.0.0/24"     # snet-appgw
API_SUBNET_CIDR="10.10.2.0/24"       # <-- ajuste si besoin
API_PORT="8000"

NSG="nsg-api-colconnect-prod"
RULE_ALLOW="allow-appgw-to-api-8000"

echo "== [CC_PATCH_LOCK_API_SUBNET_TO_APPGW_ONLY_V2] Start =="

az account show -o none

echo "== List subnets (debug) =="
az network vnet subnet list -g "$RG" --vnet-name "$VNET" \
  --query "[].{name:name,prefix:addressPrefix}" -o table

echo ""
echo "== Resolve API subnet by prefix: $API_SUBNET_CIDR =="
API_SUBNET_NAME="$(az network vnet subnet list -g "$RG" --vnet-name "$VNET" \
  --query "[?addressPrefix=='$API_SUBNET_CIDR'].name | [0]" -o tsv || true)"

if [[ -z "${API_SUBNET_NAME:-}" ]]; then
  echo "❌ Cannot find subnet with prefix=$API_SUBNET_CIDR in $VNET" >&2
  echo "   Fix: set API_SUBNET_CIDR to the correct one printed above." >&2
  exit 1
fi

echo "✅ API_SUBNET_NAME=$API_SUBNET_NAME"

echo ""
echo "== Ensure NSG exists =="
if az network nsg show -g "$RG" -n "$NSG" >/dev/null 2>&1; then
  echo "✅ NSG exists: $NSG"
else
  az network nsg create -g "$RG" -n "$NSG" -o none
  echo "✅ Created NSG: $NSG"
fi

echo ""
echo "== Upsert allow rule (AppGW subnet -> API port $API_PORT) =="
az network nsg rule create \
  -g "$RG" --nsg-name "$NSG" -n "$RULE_ALLOW" \
  --priority 200 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes "$APPGW_SUBNET_CIDR" \
  --source-port-ranges "*" \
  --destination-address-prefixes "*" \
  --destination-port-ranges "$API_PORT" \
  -o none

echo ""
echo "== Associate NSG to API subnet =="
az network vnet subnet update \
  -g "$RG" --vnet-name "$VNET" -n "$API_SUBNET_NAME" \
  --network-security-group "$NSG" \
  -o none

echo ""
echo "✅ API subnet locked: only $APPGW_SUBNET_CIDR -> TCP/$API_PORT"

echo ""
echo "== Show API subnet NSG =="
az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n "$API_SUBNET_NAME" \
  --query "{name:name,prefix:addressPrefix,nsg:networkSecurityGroup.id}" -o jsonc

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
