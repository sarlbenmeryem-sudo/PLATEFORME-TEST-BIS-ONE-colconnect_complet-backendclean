#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Probe host-from-http-settings (atomic switch to avoid Azure validation trap)
# ID: CC_PATCH_APPGW_STRICT_HEALTH_PROBE_V8_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

PROBE="probe-api-health"
BHS="bhs-api-8000"
HOST="api.colconnect.fr"

echo "== [CC_PATCH_APPGW_STRICT_HEALTH_PROBE_V8] Start =="

az account show -o none

echo "== Ensure http-settings host header is correct =="
az network application-gateway http-settings update \
  -g "$RG" --gateway-name "$APPGW" -n "$BHS" \
  --host-name "$HOST" \
  --host-name-from-backend-pool false \
  -o none

echo ""
echo "== Show probe state (before) =="
az network application-gateway probe show \
  -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
  --query "{pick:pickHostNameFromBackendHttpSettings,host:host,path:path,interval:interval,timeout:timeout,match:match.statusCodes}" -o jsonc

echo ""
echo "== Apply strict probe settings (path/status/interval/timeout) =="
az network application-gateway probe update \
  -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
  --protocol Http \
  --path "/api/v1/health" \
  --interval 15 \
  --timeout 5 \
  --match-status-codes "200-399" \
  -o none

echo ""
echo "== ATOMIC switch: pickHostNameFromBackendHttpSettings=true AND host='' in same request =="
# This avoids the contradictory validation errors (HostIsNull vs HostIsNotNull)
az network application-gateway probe update \
  -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
  --set pickHostNameFromBackendHttpSettings=true host="" \
  -o none

echo ""
echo "== Verify probe state (after) =="
az network application-gateway probe show \
  -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
  --query "{pick:pickHostNameFromBackendHttpSettings,host:host,path:path,interval:interval,timeout:timeout,unhealthyThreshold:unhealthyThreshold,match:match.statusCodes}" -o jsonc

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
