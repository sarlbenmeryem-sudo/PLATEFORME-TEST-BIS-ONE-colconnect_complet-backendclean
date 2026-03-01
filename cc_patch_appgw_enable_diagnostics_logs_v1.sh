#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: AppGW + WAF diagnostics to Log Analytics (France Central)
# ID: CC_PATCH_APPGW_ENABLE_DIAGNOSTICS_LOGS_V1_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"
LAW="law-colconnect-prod-frc"
DIAG="diag-agw-colconnect-prod"

LOCATION="francecentral"

echo "== [CC_PATCH_APPGW_ENABLE_DIAGNOSTICS_LOGS_V1] Start =="

az account show -o none

echo "== Ensure Log Analytics Workspace exists =="
if az monitor log-analytics workspace show -g "$RG" -n "$LAW" >/dev/null 2>&1; then
  echo "✅ LAW exists: $LAW"
else
  az monitor log-analytics workspace create \
    -g "$RG" -n "$LAW" -l "$LOCATION" \
    --sku PerGB2018 \
    -o none
  echo "✅ Created LAW: $LAW"
fi

LAW_ID="$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query id -o tsv)"
APPGW_ID="$(az network application-gateway show -g "$RG" -n "$APPGW" --query id -o tsv)"

echo ""
echo "== Upsert Diagnostic Setting on AppGW =="
# If exists, delete then recreate (idempotent)
if az monitor diagnostic-settings show --resource "$APPGW_ID" --name "$DIAG" >/dev/null 2>&1; then
  az monitor diagnostic-settings delete --resource "$APPGW_ID" --name "$DIAG" -o none
  echo "ℹ️ Deleted existing diagnostic setting: $DIAG"
fi

az monitor diagnostic-settings create \
  --resource "$APPGW_ID" \
  --name "$DIAG" \
  --workspace "$LAW_ID" \
  --logs '[
    {"category":"ApplicationGatewayAccessLog","enabled":true},
    {"category":"ApplicationGatewayPerformanceLog","enabled":true},
    {"category":"ApplicationGatewayFirewallLog","enabled":true}
  ]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]' \
  -o none

echo "✅ Diagnostics enabled: $DIAG -> $LAW"

echo ""
echo "== Verify diagnostic settings =="
az monitor diagnostic-settings list --resource "$APPGW_ID" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
