#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Strict probe + Host header (AppGW)
# ID: CC_PATCH_APPGW_STRICT_HEALTH_PROBE_V3_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

PROBE="probe-api-health"
BHS="bhs-api-8000"
HOST="api.colconnect.fr"

echo "== [CC_PATCH_APPGW_STRICT_HEALTH_PROBE_V3] Start =="

az account show -o none

echo "== Update http-settings (host header + disable host from backend pool) =="
az network application-gateway http-settings update \
  -g "$RG" --gateway-name "$APPGW" -n "$BHS" \
  --host-name "$HOST" \
  --host-name-from-backend-pool false \
  -o none

echo ""
echo "== Update probe strict path + take host from http-settings =="
# NOTE: --host-name-from-http-settings is the correct CLI flag
az network application-gateway probe update \
  -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
  --protocol Http \
  --path "/api/v1/health" \
  --interval 15 \
  --timeout 5 \
  --unhealthy-threshold 2 \
  --match-status-codes "200-399" \
  --host-name-from-http-settings true \
  -o none

echo ""
echo "== Quick verify (probe + http-settings) =="
echo "-- PROBE --"
az network application-gateway probe show \
  -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
  --query "{name:name,protocol:protocol,path:path,interval:interval,timeout:timeout,unhealthyThreshold:unhealthyThreshold,host:host,pickHostNameFromBackendHttpSettings:pickHostNameFromBackendHttpSettings,match:match.statusCodes}" -o jsonc

echo ""
echo "-- HTTP-SETTINGS --"
az network application-gateway http-settings show \
  -g "$RG" --gateway-name "$APPGW" -n "$BHS" \
  --query "{name:name,protocol:protocol,port:port,hostName:hostName,pickHostNameFromBackendAddress:pickHostNameFromBackendAddress,requestTimeout:requestTimeout,probe:probe.id}" -o jsonc

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
