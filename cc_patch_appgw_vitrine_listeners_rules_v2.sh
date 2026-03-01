#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Create/Update AppGW listeners + rules for colconnect.fr (root) and www redirect
# ID: CC_PATCH_APPGW_VITRINE_LISTENERS_RULES_V2_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

ROOT_DOMAIN="colconnect.fr"
WWW_DOMAIN="www.colconnect.fr"

BP="bp-web-static"
BHS="bhs-web-static-https"
LST_ROOT="lst-https-web-root"
LST_WWW="lst-https-web-www"
RULE_ROOT="rule-https-web-root"
RULE_WWW="rule-https-web-www-redirect"
REDIR_WWW="redir-www-to-root"

SSL_CERT="ssl-colconnect-fr"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing $1" >&2; exit 1; }; }
need az

az account show -o none

az_retry() {
  local max=14 n=1 delay=8
  while true; do
    set +e
    out="$("$@" 2>&1)"; code=$?
    set -e
    if [[ $code -eq 0 ]]; then return 0; fi
    if echo "$out" | grep -Eqi "PutApplicationGatewayOperation|Another operation is in progress|OperationPreempted|was being modified|TooManyRequests|429|timeout|temporar|Transient"; then
      if [[ $n -ge $max ]]; then
        echo "❌ Retry exhausted ($max). Last error:" >&2
        echo "$out" >&2
        return 1
      fi
      echo "⏳ AppGW busy/transient (retry $n/$max) in ${delay}s..."
      sleep "$delay"; n=$((n+1)); delay=$((delay+6))
      continue
    fi
    echo "❌ Azure command failed:" >&2
    echo "$out" >&2
    return 1
  done
}

echo "== [1] Ensure SSL cert exists on AppGW: $SSL_CERT =="
az network application-gateway ssl-cert show -g "$RG" --gateway-name "$APPGW" -n "$SSL_CERT" -o none

echo "== [2] Frontend port 443 name =="
fp443="$(az network application-gateway frontend-port list -g "$RG" --gateway-name "$APPGW" --query "[?port==\`443\`].name|[0]" -o tsv)"
if [[ -z "${fp443:-}" ]]; then
  echo "❌ No frontend port 443 found on AppGW" >&2
  exit 1
fi
echo "FrontendPort443: $fp443"

echo ""
echo "== [3] Ensure redirect config www -> root =="
if az network application-gateway redirect-config show -g "$RG" --gateway-name "$APPGW" -n "$REDIR_WWW" >/dev/null 2>&1; then
  echo "✅ Redirect exists: $REDIR_WWW"
else
  az_retry az network application-gateway redirect-config create -g "$RG" --gateway-name "$APPGW" -n "$REDIR_WWW" \
    --type Permanent --include-path true --include-query-string true --target-url "https://${ROOT_DOMAIN}" -o none
  echo "✅ Redirect created"
fi

echo ""
echo "== [4] Ensure listeners =="
if az network application-gateway http-listener show -g "$RG" --gateway-name "$APPGW" -n "$LST_ROOT" >/dev/null 2>&1; then
  az_retry az network application-gateway http-listener update -g "$RG" --gateway-name "$APPGW" -n "$LST_ROOT" \
    --frontend-port "$fp443" --ssl-cert "$SSL_CERT" --host-name "$ROOT_DOMAIN" -o none
else
  az_retry az network application-gateway http-listener create -g "$RG" --gateway-name "$APPGW" -n "$LST_ROOT" \
    --frontend-port "$fp443" --ssl-cert "$SSL_CERT" --host-name "$ROOT_DOMAIN" -o none
fi
echo "✅ Listener root ready"

if az network application-gateway http-listener show -g "$RG" --gateway-name "$APPGW" -n "$LST_WWW" >/dev/null 2>&1; then
  az_retry az network application-gateway http-listener update -g "$RG" --gateway-name "$APPGW" -n "$LST_WWW" \
    --frontend-port "$fp443" --ssl-cert "$SSL_CERT" --host-name "$WWW_DOMAIN" -o none
else
  az_retry az network application-gateway http-listener create -g "$RG" --gateway-name "$APPGW" -n "$LST_WWW" \
    --frontend-port "$fp443" --ssl-cert "$SSL_CERT" --host-name "$WWW_DOMAIN" -o none
fi
echo "✅ Listener www ready"

echo ""
echo "== [5] Ensure rules =="
if az network application-gateway rule show -g "$RG" --gateway-name "$APPGW" -n "$RULE_ROOT" >/dev/null 2>&1; then
  az_retry az network application-gateway rule update -g "$RG" --gateway-name "$APPGW" -n "$RULE_ROOT" \
    --http-listener "$LST_ROOT" --rule-type Basic --address-pool "$BP" --http-settings "$BHS" -o none
else
  az_retry az network application-gateway rule create -g "$RG" --gateway-name "$APPGW" -n "$RULE_ROOT" \
    --http-listener "$LST_ROOT" --rule-type Basic --address-pool "$BP" --http-settings "$BHS" -o none
fi
echo "✅ Rule root -> storage ready"

if az network application-gateway rule show -g "$RG" --gateway-name "$APPGW" -n "$RULE_WWW" >/dev/null 2>&1; then
  az_retry az network application-gateway rule update -g "$RG" --gateway-name "$APPGW" -n "$RULE_WWW" \
    --http-listener "$LST_WWW" --rule-type Basic --redirect-config "$REDIR_WWW" -o none
else
  az_retry az network application-gateway rule create -g "$RG" --gateway-name "$APPGW" -n "$RULE_WWW" \
    --http-listener "$LST_WWW" --rule-type Basic --redirect-config "$REDIR_WWW" -o none
fi
echo "✅ Rule www -> redirect ready"

echo ""
echo "== [6] Backend health =="
az network application-gateway show-backend-health -g "$RG" -n "$APPGW" -o table || true

echo ""
echo "== Rollback Git (1 step) =="
echo "git reset --hard HEAD~1"
echo "== Done =="
