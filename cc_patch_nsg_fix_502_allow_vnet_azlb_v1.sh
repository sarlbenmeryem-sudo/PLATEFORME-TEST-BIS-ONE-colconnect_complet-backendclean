#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Fix 502 by allowing VNet + AzureLoadBalancer to API port 8000 (keep deny-any)
# ID: CC_PATCH_NSG_FIX_502_ALLOW_VNET_AZLB_V1_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"
NSG="nsg-colconnect-vmss-api-prod-frc"
API_PORT="8000"
API_HOST="api.colconnect.fr"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing $1" >&2; exit 1; }; }
need az
need curl

az account show -o none

az_retry() {
  local max=12 n=1 delay=6
  while true; do
    set +e
    out="$("$@" 2>&1)"; code=$?
    set -e
    if [[ $code -eq 0 ]]; then return 0; fi
    if echo "$out" | grep -Eqi "Another operation is in progress|OperationPreempted|TooManyRequests|429|timeout|temporar|Transient"; then
      if [[ $n -ge $max ]]; then
        echo "❌ Retry exhausted ($max). Last error:" >&2
        echo "$out" >&2
        return 1
      fi
      echo "⏳ Azure transient error (retry $n/$max) in ${delay}s..."
      sleep "$delay"; n=$((n+1)); delay=$((delay+4))
      continue
    fi
    echo "❌ Azure command failed:" >&2
    echo "$out" >&2
    return 1
  done
}

echo "== [1] Ensure NSG exists =="
az network nsg show -g "$RG" -n "$NSG" -o none

echo ""
echo "== [2] Upsert allow rules for VirtualNetwork + AzureLoadBalancer -> $API_PORT =="

# Delete if exist (idempotent)
az network nsg rule delete -g "$RG" --nsg-name "$NSG" -n "cc-allow-vnet-to-api-8000" >/dev/null 2>&1 || true
az network nsg rule delete -g "$RG" --nsg-name "$NSG" -n "cc-allow-azlb-to-api-8000" >/dev/null 2>&1 || true

az_retry az network nsg rule create -g "$RG" --nsg-name "$NSG" -n "cc-allow-vnet-to-api-8000" \
  --priority 210 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes "VirtualNetwork" --source-port-ranges "*" \
  --destination-address-prefixes "*" --destination-port-ranges "$API_PORT" \
  --description "CC: Allow VirtualNetwork -> API $API_PORT (prevents AppGW/backend path issues)" \
  -o none

az_retry az network nsg rule create -g "$RG" --nsg-name "$NSG" -n "cc-allow-azlb-to-api-8000" \
  --priority 211 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes "AzureLoadBalancer" --source-port-ranges "*" \
  --destination-address-prefixes "*" --destination-port-ranges "$API_PORT" \
  --description "CC: Allow AzureLoadBalancer -> API $API_PORT (health probes plumbing)" \
  -o none

echo "✅ Allow rules added"

echo ""
echo "== [3] Show CC rules =="
az network nsg rule list -g "$RG" --nsg-name "$NSG" \
  --query "[?starts_with(name,'cc-')].[priority,name,access,sourceAddressPrefix,destinationPortRange]" -o table

echo ""
echo "== [4] AppGW backend health =="
az network application-gateway show-backend-health -g "$RG" -n "$APPGW" -o table || true

echo ""
echo "== [5] Runtime check (expect 200) =="
curl -sSI "https://${API_HOST}/api/v1/health" | sed -n '1,12p'
curl -fsS "https://${API_HOST}/api/v1/health" && echo ""

echo ""
echo "== Rollback Git (1 step) =="
echo "git reset --hard HEAD~1"

echo "== Done =="
