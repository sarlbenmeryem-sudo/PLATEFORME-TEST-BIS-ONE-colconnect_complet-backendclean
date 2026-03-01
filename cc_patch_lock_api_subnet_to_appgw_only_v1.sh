#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

# backend ILB target
BACKEND_IP="10.10.2.10"

APPGW_SUBNET_CIDR="10.10.0.0/24"   # snet-appgw
API_PORT="8000"

NSG="nsg-api-colconnect-prod"
RULE_ALLOW="allow-appgw-to-api-8000"

echo "== [CC_PATCH_LOCK_API_SUBNET_TO_APPGW_ONLY_V1] Start =="

echo "== Resolve API subnet (where backend IP lives) =="
# Find NIC(s) with that IP
NIC_ID="$(az network nic list -g "$RG" --query "[?ipConfigurations[?privateIpAddress=='$BACKEND_IP']].id | [0]" -o tsv || true)"
if [[ -z "${NIC_ID:-}" ]]; then
  echo "❌ Cannot find NIC with private IP $BACKEND_IP in RG $RG" >&2
  echo "   If backend is an ILB frontend IP, we will resolve the subnet via ILB instead." >&2
fi

SUBNET_ID=""
if [[ -n "${NIC_ID:-}" ]]; then
  SUBNET_ID="$(az network nic show --ids "$NIC_ID" --query "ipConfigurations[0].subnet.id" -o tsv)"
else
  # fallback: try ILB frontend IP config lookup (common if IP is on LB)
  ILB_ID="$(az network lb list -g "$RG" --query "[?frontendIpConfigurations[?privateIpAddress=='$BACKEND_IP']].id | [0]" -o tsv || true)"
  if [[ -z "${ILB_ID:-}" ]]; then
    echo "❌ Cannot find LB frontend IP with $BACKEND_IP either." >&2
    exit 1
  fi
  SUBNET_ID="$(az network lb show --ids "$ILB_ID" --query "frontendIpConfigurations[0].subnet.id" -o tsv)"
fi

echo "SUBNET_ID=$SUBNET_ID"
VNET_NAME="$(echo "$SUBNET_ID" | awk -F'/' '{for(i=1;i<=NF;i++) if($i=="virtualNetworks") print $(i+1)}')"
SUBNET_NAME="$(echo "$SUBNET_ID" | awk -F'/' '{for(i=1;i<=NF;i++) if($i=="subnets") print $(i+1)}')"

echo "VNET=$VNET_NAME SUBNET=$SUBNET_NAME"

echo ""
echo "== Ensure NSG exists =="
if az network nsg show -g "$RG" -n "$NSG" >/dev/null 2>&1; then
  echo "✅ NSG exists: $NSG"
else
  az network nsg create -g "$RG" -n "$NSG" -o none
  echo "✅ Created NSG: $NSG"
fi

echo ""
echo "== Upsert allow rule (AppGW subnet -> API port) =="
# Priority: 200 (leave room for emergency rules <200)
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
  -g "$RG" --vnet-name "$VNET_NAME" -n "$SUBNET_NAME" \
  --network-security-group "$NSG" \
  -o none

echo "✅ API subnet locked: only AppGW subnet can reach TCP/$API_PORT"

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
