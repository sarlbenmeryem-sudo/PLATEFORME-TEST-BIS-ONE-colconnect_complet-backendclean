#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Strict probe + Host header (fix host not null)
# ID: CC_PATCH_APPGW_STRICT_HEALTH_PROBE_V5_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

PROBE="probe-api-health"
BHS="bhs-api-8000"
HOST="api.colconnect.fr"

echo "== [CC_PATCH_APPGW_STRICT_HEALTH_PROBE_V5] Start =="

az account show -o none

echo "== Update http-settings (force Host header) =="
az network application-gateway http-settings update \
  -g "$RG" --gateway-name "$APPGW" -n "$BHS" \
  --host-name "$HOST" \
  --host-name-from-backend-pool false \
  -o none

echo ""
echo "== Clear probe.host (must be empty when pickHostNameFromBackendHttpSettings=true) =="
# Clear existing host (e.g., 10.10.2.10) to satisfy AppGW constraint
az network application-gateway probe update \
  -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
  --set host="" \
  -o none

echo ""
echo "== Apply strict probe settings + pick host from http-settings =="
az network application-gateway probe update \
  -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
  --protocol Http \
  --path "/api/v1/health" \
  --interval 15 \
  --timeout 5 \
  --match-status-codes "200-399" \
  --host-name-from-http-settings true \
  -o none

echo ""
echo "== Try set unhealthy threshold ONLY if CLI supports it =="
HELP_TXT="$(az network application-gateway probe update -h 2>/dev/null || true)"
if echo "$HELP_TXT" | grep -q -- "--unhealthy-threshold"; then
  az network application-gateway probe update \
    -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
    --unhealthy-threshold 2 \
    -o none
  echo "✅ unhealthy-threshold set to 2"
else
  echo "ℹ️ CLI does NOT support --unhealthy-threshold here -> keeping existing value"
fi

echo ""
echo "== Verify probe =="
az network application-gateway probe show \
  -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
  --query "{name:name,protocol:protocol,path:path,interval:interval,timeout:timeout,unhealthyThreshold:unhealthyThreshold,host:host,pickHostNameFromBackendHttpSettings:pickHostNameFromBackendHttpSettings,match:match.statusCodes}" -o jsonc

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
