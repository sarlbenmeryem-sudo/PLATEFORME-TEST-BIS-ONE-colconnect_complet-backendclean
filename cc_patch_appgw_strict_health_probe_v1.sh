#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

PROBE="probe-api-health"
BHS="bhs-api-8000"
HOST="api.colconnect.fr"

echo "== [CC_PATCH_APPGW_STRICT_HEALTH_PROBE_V1] Start =="

echo "== Update probe: path=/api/v1/health and host header =="
az network application-gateway probe update \
  -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
  --protocol Http \
  --path "/api/v1/health" \
  --interval 20 \
  --timeout 10 \
  --unhealthy-threshold 2 \
  --host-name "$HOST" \
  -o none

echo "== Update http-settings to use hostName (avoid wrong host routing) =="
az network application-gateway http-settings update \
  -g "$RG" --gateway-name "$APPGW" -n "$BHS" \
  --host-name "$HOST" \
  --pick-hostname-from-backend-address false \
  -o none

echo "✅ Probe + http-settings hardened"

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
