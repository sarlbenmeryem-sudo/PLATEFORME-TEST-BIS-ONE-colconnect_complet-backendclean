#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: NSG Lockdown VMSS subnet for API port 8000 (AppGW-only)
# ID: CC_PATCH_NSG_LOCKDOWN_VMSS_SUBNET_V2_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"
VMSS="vmss-api-colconnect-prod"
NSG="nsg-colconnect-vmss-api-prod-frc"

API_PORT="8000"

echo "== [CC_PATCH_NSG_LOCKDOWN_VMSS_SUBNET_V2_20260301] Start =="

need() { command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing $1" >&2; exit 1; }; }
need az
need jq

az account show -o none

az_retry() {
  local max=12
  local n=1
  local delay=6
  while true; do
    set +e
    out="$("$@" 2>&1)"
    code=$?
    set -e
    if [[ $code -eq 0 ]]; then
      return 0
    fi
    if echo "$out" | grep -Eqi "PutApplicationGatewayOperation|Another operation is in progress|OperationPreempted|was being modified|TooManyRequests|429|timeout|temporar|Transient|RetryableError"; then
      if [[ $n -ge $max ]]; then
        echo "❌ Retry exhausted ($max). Last error:" >&2
        echo "$out" >&2
        return 1
      fi
      echo "⏳ Azure transient error (retry $n/$max) in ${delay}s..."
      sleep "$delay"
      n=$((n+1))
      delay=$((delay+4))
      continue
    fi
    echo "❌ Azure command failed:" >&2
    echo "$out" >&2
    return 1
  done
}

echo ""
echo "== [1] Discover AppGW subnet and VMSS subnet IDs =="

appgw_subnet_id="$(az network application-gateway show -g "$RG" -n "$APPGW" --query "gatewayIpConfigurations[0].subnet.id" -o tsv)"
if [[ -z "${appgw_subnet_id:-}" ]]; then
  echo "❌ Could not resolve AppGW subnet id" >&2
  exit 1
fi

vmss_subnet_id="$(az vmss show -g "$RG" -n "$VMSS" --query "virtualMachineProfile.networkProfile.networkInterfaceConfigurations[0].ipConfigurations[0].subnet.id" -o tsv)"
if [[ -z "${vmss_subnet_id:-}" ]]; then
  echo "❌ Could not resolve VMSS subnet id" >&2
  exit 1
fi

appgw_vnet="$(echo "$appgw_subnet_id" | awk -F/ '{for(i=1;i<=NF;i++){if($i=="virtualNetworks"){print $(i+1); exit}}}')"
appgw_subnet="$(echo "$appgw_subnet_id" | awk -F/ '{for(i=1;i<=NF;i++){if($i=="subnets"){print $(i+1); exit}}}')"

vmss_vnet="$(echo "$vmss_subnet_id" | awk -F/ '{for(i=1;i<=NF;i++){if($i=="virtualNetworks"){print $(i+1); exit}}}')"
vmss_subnet="$(echo "$vmss_subnet_id" | awk -F/ '{for(i=1;i<=NF;i++){if($i=="subnets"){print $(i+1); exit}}}')"

echo "AppGW subnet: $appgw_vnet/$appgw_subnet"
echo "VMSS  subnet: $vmss_vnet/$vmss_subnet"

echo ""
echo "== [2] Fetch subnet CIDR prefixes =="

appgw_prefixes="$(az network vnet subnet show -g "$RG" --vnet-name "$appgw_vnet" -n "$appgw_subnet" --query "addressPrefixes" -o json)"
vmss_prefixes="$(az network vnet subnet show -g "$RG" --vnet-name "$vmss_vnet" -n "$vmss_subnet" --query "addressPrefixes" -o json)"

echo "AppGW prefixes: $appgw_prefixes"
echo "VMSS  prefixes: $vmss_prefixes"

prefix_count="$(echo "$appgw_prefixes" | jq 'length')"
if [[ "$prefix_count" -lt 1 ]]; then
  echo "❌ No addressPrefixes found for AppGW subnet" >&2
  exit 1
fi

echo ""
echo "== [3] Ensure NSG exists =="

if az network nsg show -g "$RG" -n "$NSG" >/dev/null 2>&1; then
  echo "✅ NSG exists: $NSG"
else
  az_retry az network nsg create -g "$RG" -n "$NSG" -o none
  echo "✅ NSG created: $NSG"
fi

echo ""
echo "== [4] Upsert inbound rules (AppGW-only -> 8000, deny any -> 8000) =="

# delete previous rules we manage (idempotent)
# allow rules might be indexed
existing_allow="$(az network nsg rule list -g "$RG" --nsg-name "$NSG" --query "[?starts_with(name,'allow-appgw-to-api-8000-')].name" -o tsv || true)"
for r in $existing_allow; do
  az network nsg rule delete -g "$RG" --nsg-name "$NSG" -n "$r" >/dev/null 2>&1 || true
done
az network nsg rule delete -g "$RG" --nsg-name "$NSG" -n "deny-any-to-api-8000" >/dev/null 2>&1 || true

# allow from each appgw prefix
prio=200
for i in $(seq 0 $((prefix_count-1))); do
  src_prefix="$(echo "$appgw_prefixes" | jq -r ".[$i]")"
  rule_name="allow-appgw-to-api-8000-$i"
  az_retry az network nsg rule create -g "$RG" --nsg-name "$NSG" -n "$rule_name" \
    --priority "$prio" \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes "$src_prefix" \
    --source-port-ranges "*" \
    --destination-address-prefixes "*" \
    --destination-port-ranges "$API_PORT" \
    --description "Allow AppGW subnet $src_prefix -> VMSS API port $API_PORT" \
    -o none
  echo "✅ Allow rule: $rule_name (prio $prio)"
  prio=$((prio+1))
done

# deny all inbound to API port
az_retry az network nsg rule create -g "$RG" --nsg-name "$NSG" -n "deny-any-to-api-8000" \
  --priority 300 \
  --direction Inbound \
  --access Deny \
  --protocol Tcp \
  --source-address-prefixes "*" \
  --source-port-ranges "*" \
  --destination-address-prefixes "*" \
  --destination-port-ranges "$API_PORT" \
  --description "Deny direct inbound to API port $API_PORT from anywhere (forces AppGW-only)" \
  -o none
echo "✅ Deny rule: deny-any-to-api-8000 (prio 300)"

echo ""
echo "== [5] Attach NSG to VMSS subnet =="

az_retry az network vnet subnet update -g "$RG" --vnet-name "$vmss_vnet" -n "$vmss_subnet" \
  --network-security-group "$NSG" -o none

echo "✅ NSG attached to subnet: $vmss_vnet/$vmss_subnet"

echo ""
echo "== [6] Post-check: list inbound rules (managed subset) =="

az network nsg rule list -g "$RG" --nsg-name "$NSG" \
  --query "[?contains(name,'api-8000')].[priority,name,access,sourceAddressPrefix,destinationPortRange]" -o table

echo ""
echo "== [7] AppGW backend health sanity =="

az network application-gateway show-backend-health -g "$RG" -n "$APPGW" -o table || true

echo ""
echo "== Rollback Git (1 step) =="
echo "git reset --hard HEAD~1"

echo ""
echo "== [CC_PATCH_NSG_LOCKDOWN_VMSS_SUBNET_V2_20260301] Done =="
