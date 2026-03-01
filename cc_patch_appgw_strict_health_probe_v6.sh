#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Strict probe + Host header (state-aware Azure constraints)
# ID: CC_PATCH_APPGW_STRICT_HEALTH_PROBE_V6_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

PROBE="probe-api-health"
BHS="bhs-api-8000"
HOST="api.colconnect.fr"

echo "== [CC_PATCH_APPGW_STRICT_HEALTH_PROBE_V6] Start =="

az account show -o none

echo "== Update http-settings (force Host header) =="
az network application-gateway http-settings update \
  -g "$RG" --gateway-name "$APPGW" -n "$BHS" \
  --host-name "$HOST" \
  --host-name-from-backend-pool false \
  -o none

echo ""
echo "== Read current probe state =="
PICK="$(az network application-gateway probe show -g "$RG" --gateway-name "$APPGW" -n "$PROBE" --query pickHostNameFromBackendHttpSettings -o tsv)"
CUR_HOST="$(az network application-gateway probe show -g "$RG" --gateway-name "$APPGW" -n "$PROBE" --query host -o tsv)"

echo "pickHostNameFromBackendHttpSettings=$PICK"
echo "probe.host='${CUR_HOST:-}'"

echo ""
echo "== Ensure strict probe settings (path/status/interval/timeout) without toggling host yet =="
az network application-gateway probe update \
  -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
  --protocol Http \
  --path "/api/v1/health" \
  --interval 15 \
  --timeout 5 \
  --match-status-codes "200-399" \
  -o none

echo ""
if [[ "$PICK" != "true" ]]; then
  echo "== pickHostNameFromBackendHttpSettings is FALSE -> set host to a valid value first =="
  # Azure requires host NOT NULL when pick=false
  az network application-gateway probe update \
    -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
    --host-name "$HOST" \
    -o none

  echo "== Now enable pickHostNameFromBackendHttpSettings from http-settings =="
  az network application-gateway probe update \
    -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
    --host-name-from-http-settings true \
    -o none
else
  echo "== pickHostNameFromBackendHttpSettings already TRUE -> ok =="
fi

echo ""
echo "== Now clear host (must be empty when pickHostNameFromBackendHttpSettings=true) =="
# Only valid after pick=true
az network application-gateway probe update \
  -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
  --set host="" \
  -o none

echo ""
echo "== Verify probe final state =="
az network application-gateway probe show \
  -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
  --query "{name:name,protocol:protocol,path:path,interval:interval,timeout:timeout,unhealthyThreshold:unhealthyThreshold,host:host,pickHostNameFromBackendHttpSettings:pickHostNameFromBackendHttpSettings,match:match.statusCodes}" -o jsonc

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
