#!/usr/bin/env bash
set -euo pipefail
RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"
URLMAP="upm-colconnect"
RULE="api-rule"

echo "== Current paths =="
az network application-gateway url-path-map rule show -g "$RG" --gateway-name "$APPGW" --path-map-name "$URLMAP" -n "$RULE" --query "paths" -o tsv

echo "== Add /api (keep /api/*) =="
az network application-gateway url-path-map rule update \
  -g "$RG" --gateway-name "$APPGW" --path-map-name "$URLMAP" -n "$RULE" \
  --paths "/api" "/api/*" -o none

echo "✅ Updated paths"
echo "Rollback (git): git reset --hard HEAD~1"
