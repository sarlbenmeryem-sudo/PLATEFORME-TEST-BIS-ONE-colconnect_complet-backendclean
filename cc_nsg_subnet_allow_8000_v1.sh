#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
VNET="vnet-colconnect-prod-frc"
SUBNET="snet-api"

RULE_LB="allow-azlb-8000"
RULE_VNET="allow-vnet-8000"
NSG_FALLBACK="nsg-snet-api"

echo "== Detect NSG on subnet $VNET/$SUBNET =="
NSG_ID="$(az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n "$SUBNET" --query "networkSecurityGroup.id" -o tsv)"
if [[ -z "${NSG_ID:-}" ]]; then
  echo "⚠️ No NSG attached to subnet. Creating + attaching $NSG_FALLBACK"
  az network nsg create -g "$RG" -n "$NSG_FALLBACK" -o none
  az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n "$SUBNET" --network-security-group "$NSG_FALLBACK" -o none
  NSG_NAME="$NSG_FALLBACK"
else
  NSG_NAME="$(az resource show --ids "$NSG_ID" --query name -o tsv)"
fi

echo "NSG_NAME=$NSG_NAME"

echo "== Rule 1: allow AzureLoadBalancer probe/data to 8000 =="
az network nsg rule create \
  -g "$RG" --nsg-name "$NSG_NAME" -n "$RULE_LB" \
  --priority 200 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes AzureLoadBalancer \
  --source-port-ranges "*" \
  --destination-address-prefixes "*" \
  --destination-port-ranges 8000 \
  -o none

echo "== Rule 2: allow VNet (east-west) to 8000 (for AppGW/front/bastion) =="
az network nsg rule create \
  -g "$RG" --nsg-name "$NSG_NAME" -n "$RULE_VNET" \
  --priority 210 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes VirtualNetwork \
  --source-port-ranges "*" \
  --destination-address-prefixes "*" \
  --destination-port-ranges 8000 \
  -o none

echo "✅ NSG rules applied on subnet NSG: $NSG_NAME"
echo "Rollback (git): git reset --hard HEAD~1"
