#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"
PROBE="probe-front"

echo "== [CC_PATCH_APPGW_FRONT_PROBE_FIX_V1] Start =="

WEB_HOST="$(az storage account show -g "$RG" -n stcolconnectfrontfrc01 --query "primaryEndpoints.web" -o tsv | sed 's|https://||; s|/||')"
echo "WEB_HOST=$WEB_HOST"

az network application-gateway probe create \
  -g "$RG" \
  --gateway-name "$APPGW" \
  -n "$PROBE" \
  --protocol Https \
  --host "$WEB_HOST" \
  --path "/" \
  --interval 30 \
  --timeout 30 \
  --threshold 3 \
  -o none

echo "✅ Probe recreated with host header"

echo "== Done =="
