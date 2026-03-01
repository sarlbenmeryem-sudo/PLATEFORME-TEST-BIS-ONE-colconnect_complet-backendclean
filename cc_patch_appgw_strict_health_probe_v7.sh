#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Strict probe -> pick host from http-settings (no ambiguous flags)
# ID: CC_PATCH_APPGW_STRICT_HEALTH_PROBE_V7_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

PROBE="probe-api-health"
BHS="bhs-api-8000"
HOST="api.colconnect.fr"

echo "== [CC_PATCH_APPGW_STRICT_HEALTH_PROBE_V7] Start =="

az account show -o none

echo "== Ensure http-settings has correct Host header =="
az network application-gateway http-settings update \
  -g "$RG" --gateway-name "$APPGW" -n "$BHS" \
  --host-name "$HOST" \
  --host-name-from-backend-pool false \
  -o none

echo ""
echo "== Read probe state (before) =="
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
echo "== Step 1: make sure host is NON-empty while pickHostNameFromBackendHttpSettings is false =="
# Use --set host=... to avoid ambiguous --host-name
az network application-gateway probe update \
  -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
  --set host="$HOST" \
  -o none

echo ""
echo "== Step 2: enable pickHostNameFromBackendHttpSettings (host will be taken from http-settings) =="
# Use the full option name to avoid ambiguity
az network application-gateway probe update \
  -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
  --host-name-from-http-settings true \
  -o none

echo ""
echo "== Step 3: clear host (must be empty when pickHostNameFromBackendHttpSettings=true) =="
az network application-gateway probe update \
  -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
  --set host="" \
  -o none

echo ""
echo "== Verify probe state (after) =="
az network application-gateway probe show \
  -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
  --query "{pick:pickHostNameFromBackendHttpSettings,host:host,path:path,interval:interval,timeout:timeout,unhealthyThreshold:unhealthyThreshold,match:match.statusCodes}" -o jsonc

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
