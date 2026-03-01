#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"
API_HOST="api.colconnect.fr"
NSG="nsg-colconnect-vmss-api-prod-frc"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing $1" >&2; exit 1; }; }
need az
need curl

az account show -o none

echo "== [1] HTTP -> HTTPS redirect =="
curl -sSI "http://${API_HOST}/api/v1/health" | sed -n '1,12p'

echo ""
echo "== [2] HTTPS health =="
curl -fsS "https://${API_HOST}/api/v1/health" && echo ""

echo ""
echo "== [3] AppGW backend health (must show Healthy) =="
az network application-gateway show-backend-health -g "$RG" -n "$APPGW" -o table

echo ""
echo "== [4] WAF policy mode/state (attached to AppGW) =="
policy_id="$(az network application-gateway show -g "$RG" -n "$APPGW" --query "firewallPolicy.id" -o tsv)"
policy_name="$(echo "$policy_id" | awk -F/ '{print $NF}')"
echo "Policy: $policy_name"
az network application-gateway waf-policy show -g "$RG" -n "$policy_name" --query "{mode:policySettings.mode,state:policySettings.state}" -o table

echo ""
echo "== [5] NSG rules (cc-*) =="
az network nsg rule list -g "$RG" --nsg-name "$NSG" \
  --query "[?starts_with(name,'cc-')].[priority,name,access,sourceAddressPrefix,destinationPortRange]" -o table

echo ""
echo "== Rollback Git (1 step) =="
echo "git reset --hard HEAD~1"

echo "== Done =="
