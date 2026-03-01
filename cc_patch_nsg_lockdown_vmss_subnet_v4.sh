#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: NSG Lockdown VMSS subnet (AppGW-only -> 8000) - robust subnet discovery
# ID: CC_PATCH_NSG_LOCKDOWN_VMSS_SUBNET_V4_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"
VMSS="vmss-api-colconnect-prod"

API_PORT="8000"
NSG_DESIRED="nsg-colconnect-vmss-api-prod-frc"

echo "== [CC_PATCH_NSG_LOCKDOWN_VMSS_SUBNET_V4_20260301] Start =="

need(){ command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing $1" >&2; exit 1; }; }
need az
need jq

az account show -o none

az_retry() {
  local max=12 n=1 delay=6
  while true; do
    set +e
    out="$("$@" 2>&1)"; code=$?
    set -e
    if [[ $code -eq 0 ]]; then return 0; fi
    if echo "$out" | grep -Eqi "PutApplicationGatewayOperation|Another operation is in progress|OperationPreempted|was being modified|TooManyRequests|429|timeout|temporar|Transient"; then
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

echo ""
echo "== [1] Discover AppGW subnet id (robust) =="

# Try gatewayIpConfigurations first, then frontendIPConfigurations
appgw_subnet_id="$(az network application-gateway show -g "$RG" -n "$APPGW" --query "gatewayIpConfigurations[0].subnet.id" -o tsv 2>/dev/null || true)"
if [[ -z "${appgw_subnet_id:-}" || "$appgw_subnet_id" == "null" ]]; then
  appgw_subnet_id="$(az network application-gateway show -g "$RG" -n "$APPGW" --query "frontendIPConfigurations[0].subnet.id" -o tsv 2>/dev/null || true)"
fi

# Extra fallback: scan full JSON
if [[ -z "${appgw_subnet_id:-}" || "$appgw_subnet_id" == "null" ]]; then
  appgw_subnet_id="$(az network application-gateway show -g "$RG" -n "$APPGW" -o json | jq -r '(
      .gatewayIpConfigurations[]?.subnet.id // empty
    )' | head -n 1)"
fi
if [[ -z "${appgw_subnet_id:-}" || "$appgw_subnet_id" == "null" ]]; then
  appgw_subnet_id="$(az network application-gateway show -g "$RG" -n "$APPGW" -o json | jq -r '(
      .frontendIPConfigurations[]?.subnet.id // empty
    )' | head -n 1)"
fi

if [[ -z "${appgw_subnet_id:-}" || "$appgw_subnet_id" == "null" ]]; then
  echo "❌ AppGW subnet not found via API. Dumping quick hints:" >&2
  az network application-gateway show -g "$RG" -n "$APPGW" --query "{gw:gatewayIpConfigurations[].subnet.id,fe:frontendIPConfigurations[].subnet.id}" -o json | jq . >&2 || true
  exit 1
fi

echo "✅ AppGW subnet id: $appgw_subnet_id"

echo ""
echo "== [2] Discover VMSS subnet id =="

vmss_subnet_id="$(az vmss show -g "$RG" -n "$VMSS" --query "virtualMachineProfile.networkProfile.networkInterfaceConfigurations[0].ipConfigurations[0].subnet.id" -o tsv)"
if [[ -z "${vmss_subnet_id:-}" || "$vmss_subnet_id" == "null" ]]; then
  echo "❌ VMSS subnet not found" >&2
  exit 1
fi
echo "✅ VMSS subnet id: $vmss_subnet_id"

# Extract VNET/subnet names
appgw_vnet="$(echo "$appgw_subnet_id" | awk -F/ '{for(i=1;i<=NF;i++) if($i=="virtualNetworks"){print $(i+1); exit}}')"
appgw_subnet="$(echo "$appgw_subnet_id" | awk -F/ '{for(i=1;i<=NF;i++) if($i=="subnets"){print $(i+1); exit}}')"
vmss_vnet="$(echo "$vmss_subnet_id" | awk -F/ '{for(i=1;i<=NF;i++) if($i=="virtualNetworks"){print $(i+1); exit}}')"
vmss_subnet="$(echo "$vmss_subnet_id" | awk -F/ '{for(i=1;i<=NF;i++) if($i=="subnets"){print $(i+1); exit}}')"

echo "AppGW subnet: $appgw_vnet/$appgw_subnet"
echo "VMSS  subnet: $vmss_vnet/$vmss_subnet"

echo ""
echo "== [3] Get AppGW subnet prefixes =="
appgw_prefixes="$(az network vnet subnet show -g "$RG" --vnet-name "$appgw_vnet" -n "$appgw_subnet" --query "addressPrefixes" -o json)"
prefix_count="$(echo "$appgw_prefixes" | jq 'length')"
if [[ "$prefix_count" -lt 1 ]]; then echo "❌ No prefixes for AppGW subnet" >&2; exit 1; fi
echo "AppGW prefixes: $appgw_prefixes"

echo ""
echo "== [4] Ensure NSG exists =="
if az network nsg show -g "$RG" -n "$NSG_DESIRED" >/dev/null 2>&1; then
  echo "✅ NSG exists: $NSG_DESIRED"
else
  echo "Creating NSG: $NSG_DESIRED"
  az_retry az network nsg create -g "$RG" -n "$NSG_DESIRED" -o none
fi

echo ""
echo "== [5] Upsert CC rules =="
# delete existing cc rules
existing="$(az network nsg rule list -g "$RG" --nsg-name "$NSG_DESIRED" --query "[?starts_with(name,'cc-')].name" -o tsv || true)"
for r in $existing; do
  az network nsg rule delete -g "$RG" --nsg-name "$NSG_DESIRED" -n "$r" >/dev/null 2>&1 || true
done

prio=200
for i in $(seq 0 $((prefix_count-1))); do
  src_prefix="$(echo "$appgw_prefixes" | jq -r ".[$i]")"
  az_retry az network nsg rule create -g "$RG" --nsg-name "$NSG_DESIRED" -n "cc-allow-appgw-to-api-8000-$i" \
    --priority "$prio" --direction Inbound --access Allow --protocol Tcp \
    --source-address-prefixes "$src_prefix" --source-port-ranges "*" \
    --destination-address-prefixes "*" --destination-port-ranges "$API_PORT" \
    --description "CC: Allow AppGW subnet $src_prefix -> API $API_PORT" \
    -o none
  prio=$((prio+1))
done

az_retry az network nsg rule create -g "$RG" --nsg-name "$NSG_DESIRED" -n "cc-deny-any-to-api-8000" \
  --priority 300 --direction Inbound --access Deny --protocol Tcp \
  --source-address-prefixes "*" --source-port-ranges "*" \
  --destination-address-prefixes "*" --destination-port-ranges "$API_PORT" \
  --description "CC: Deny direct inbound to API port $API_PORT" \
  -o none

echo "✅ CC rules applied"

echo ""
echo "== [6] Attach NSG to VMSS subnet =="
az_retry az network vnet subnet update -g "$RG" --vnet-name "$vmss_vnet" -n "$vmss_subnet" \
  --network-security-group "$NSG_DESIRED" -o none
echo "✅ NSG attached to VMSS subnet"

echo ""
echo "== [7] Show CC rules =="
az network nsg rule list -g "$RG" --nsg-name "$NSG_DESIRED" \
  --query "[?starts_with(name,'cc-')].[priority,name,access,sourceAddressPrefix,destinationPortRange]" -o table

echo ""
echo "== [8] AppGW backend health sanity =="
az network application-gateway show-backend-health -g "$RG" -n "$APPGW" -o table || true

echo ""
echo "== Rollback Git (1 step) =="
echo "git reset --hard HEAD~1"

echo ""
echo "== [CC_PATCH_NSG_LOCKDOWN_VMSS_SUBNET_V4_20260301] Done =="
