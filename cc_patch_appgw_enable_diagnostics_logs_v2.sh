#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Register Microsoft.Insights + AppGW diagnostics -> Log Analytics
# ID: CC_PATCH_APPGW_ENABLE_DIAGNOSTICS_LOGS_V2_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"
LAW="law-colconnect-prod-frc"
DIAG="diag-agw-colconnect-prod"
LOCATION="francecentral"

echo "== [CC_PATCH_APPGW_ENABLE_DIAGNOSTICS_LOGS_V2] Start =="

az account show -o none

echo "== Ensure provider Microsoft.Insights is registered =="
STATE="$(az provider show -n Microsoft.Insights --query registrationState -o tsv || true)"
echo "Current Microsoft.Insights state: ${STATE:-unknown}"

if [[ "${STATE:-}" != "Registered" ]]; then
  echo "Registering Microsoft.Insights..."
  az provider register -n Microsoft.Insights -o none

  echo "Waiting for Microsoft.Insights to become Registered..."
  for i in {1..30}; do
    STATE="$(az provider show -n Microsoft.Insights --query registrationState -o tsv || true)"
    echo "  [$i/30] state=$STATE"
    if [[ "$STATE" == "Registered" ]]; then
      break
    fi
    sleep 5
  done

  if [[ "$STATE" != "Registered" ]]; then
    echo "❌ Microsoft.Insights not Registered after wait. Stop."
    echo "Rollback (git): git reset --hard HEAD~1"
    exit 2
  fi
fi
echo "✅ Microsoft.Insights is Registered"

echo ""
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
