#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Canonical redirect root -> www (HTTP + HTTPS)
# ID: CC_PATCH_APPGW_ROOT_TO_WWW_V1_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

L80_ROOT="lis-http-root"
L443_ROOT="lis-https-root"

RS_REDIRECT_ROOT_TO_WWW="rs-root-to-www"

RULE_HTTP_ROOT="rule-http-root"
RULE_HTTPS_ROOT="rule-https-root"

P_HTTP_ROOT="90"
P_HTTPS_ROOT="190"

echo "== [CC_PATCH_APPGW_ROOT_TO_WWW_V1] Start =="
az account show -o none

echo "== Create/Update redirect config root->www =="
az network application-gateway redirect-config create \
  -g "$RG" --gateway-name "$APPGW" \
  -n "$RS_REDIRECT_ROOT_TO_WWW" \
  --type Permanent \
  --target-url "https://www.colconnect.fr" \
  --include-path true \
  --include-query-string true \
  -o none || true

az network application-gateway redirect-config update \
  -g "$RG" --gateway-name "$APPGW" \
  -n "$RS_REDIRECT_ROOT_TO_WWW" \
  --type Permanent \
  --target-url "https://www.colconnect.fr" \
  --include-path true \
  --include-query-string true \
  -o none

echo "== Delete existing ROOT rules (safe) =="

az network application-gateway rule delete \
  -g "$RG" --gateway-name "$APPGW" \
  -n "$RULE_HTTP_ROOT" -o none || true

az network application-gateway rule delete \
  -g "$RG" --gateway-name "$APPGW" \
  -n "$RULE_HTTPS_ROOT" -o none || true

echo "== Recreate ROOT rules with redirect =="

# HTTP root → www
az network application-gateway rule create \
  -g "$RG" --gateway-name "$APPGW" \
  -n "$RULE_HTTP_ROOT" \
  --rule-type Basic \
  --http-listener "$L80_ROOT" \
  --redirect-config "$RS_REDIRECT_ROOT_TO_WWW" \
  --priority "$P_HTTP_ROOT" \
  -o none

# HTTPS root → www
az network application-gateway rule create \
  -g "$RG" --gateway-name "$APPGW" \
  -n "$RULE_HTTPS_ROOT" \
  --rule-type Basic \
  --http-listener "$L443_ROOT" \
  --redirect-config "$RS_REDIRECT_ROOT_TO_WWW" \
  --priority "$P_HTTPS_ROOT" \
  -o none

echo "== Verify rules =="
az network application-gateway rule list \
  -g "$RG" --gateway-name "$APPGW" \
  --query "[].{name:name,priority:priority,ruleType:ruleType}" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
