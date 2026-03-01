#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

PROBE="probe-api-health"
BHS="bhs-api-8000"
HOST="api.colconnect.fr"

echo "== [CC_PATCH_APPGW_STRICT_HEALTH_PROBE_V2] Start =="

az account show -o none

echo "== Update http-settings host header (bhs-api-8000) =="
az network application-gateway http-settings update \
  -g "$RG" --gateway-name "$APPGW" -n "$BHS" \
  --host-name "$HOST" \
  --pick-hostname-from-backend-address false \
  -o none

echo ""
echo "== Update probe strict path + use host from http-settings =="
az network application-gateway probe update \
  -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
  --protocol Http \
  --path "/api/v1/health" \
  --interval 20 \
  --timeout 10 \
  --unhealthy-threshold 2 \
  --host-name-from-http-settings true \
  -o none

echo "✅ Probe + http-settings hardened"

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
