#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: AppGW serve colconnect.fr from Storage Static Website (France Central)
# ID: CC_PATCH_APPGW_ADD_VITRINE_BACKEND_STORAGE_V1_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

ROOT_DOMAIN="colconnect.fr"
WWW_DOMAIN="www.colconnect.fr"

# AppGW objects
BP="bp-web-static"
BHS="bhs-web-static-https"
PROBE="probe-web-root"
LST_ROOT="lst-https-web-root"
LST_WWW="lst-https-web-www"
RULE_ROOT="rule-https-web-root"
RULE_WWW="rule-https-web-www-redirect"
REDIR_WWW="redir-www-to-root"

# Reuse or create rewrite set for security headers
REWRITE_SET="rrs-security-headers"
REWRITE_RULE="rr-security-headers"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing $1" >&2; exit 1; }; }
need az
need jq

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

echo "== [1] Auto-detect Storage Static Website host =="
# pick latest storage account in RG with web endpoint enabled
sa_json="$(az storage account list -g "$RG" -o json)"
web_host="$(echo "$sa_json" | jq -r '
  map({name:.name, web:(.primaryEndpoints.web // "")})
  | map(select(.web != ""))
  | (sort_by(.name) | last | .web) // empty
')"

if [[ -z "${web_host:-}" || "$web_host" == "null" ]]; then
  echo "❌ No storage account with primaryEndpoints.web found in RG. Run storage static patch first." >&2
  exit 1
fi

# web_host like https://<account>.z6.web.core.windows.net/
host="$(echo "$web_host" | sed -E 's#^https?://##; s#/$##')"
echo "✅ Detected web host: $host"

echo ""
echo "== [2] Ensure backend pool =="
if az network application-gateway address-pool show -g "$RG" --gateway-name "$APPGW" -n "$BP" >/dev/null 2>&1; then
  echo "✅ Backend pool exists: $BP"
else
  az_retry az network application-gateway address-pool create -g "$RG" --gateway-name "$APPGW" -n "$BP" --servers "$host" -o none
  echo "✅ Backend pool created"
fi

echo ""
echo "== [3] Ensure probe =="
if az network application-gateway probe show -g "$RG" --gateway-name "$APPGW" -n "$PROBE" >/dev/null 2>&1; then
  az_retry az network application-gateway probe update -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
    --protocol Https --path "/" --interval 30 --timeout 10 --threshold 3 -o none
  echo "✅ Probe updated"
else
  az_retry az network application-gateway probe create -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
    --protocol Https --path "/" --interval 30 --timeout 10 --threshold 3 -o none
  echo "✅ Probe created"
fi

echo ""
echo "== [4] Ensure HTTP settings =="
if az network application-gateway http-settings show -g "$RG" --gateway-name "$APPGW" -n "$BHS" >/dev/null 2>&1; then
  az_retry az network application-gateway http-settings update -g "$RG" --gateway-name "$APPGW" -n "$BHS" \
    --port 443 --protocol Https --timeout 30 --probe "$PROBE" \
    --host-name-from-backend-pool true -o none
  echo "✅ HTTP settings updated"
else
  az_retry az network application-gateway http-settings create -g "$RG" --gateway-name "$APPGW" -n "$BHS" \
    --port 443 --protocol Https --timeout 30 --probe "$PROBE" \
    --host-name-from-backend-pool true -o none
  echo "✅ HTTP settings created"
fi

echo ""
echo "== [5] Ensure redirect config www -> root =="
if az network application-gateway redirect-config show -g "$RG" --gateway-name "$APPGW" -n "$REDIR_WWW" >/dev/null 2>&1; then
  echo "✅ Redirect exists: $REDIR_WWW"
else
  az_retry az network application-gateway redirect-config create -g "$RG" --gateway-name "$APPGW" -n "$REDIR_WWW" \
    --type Permanent --include-path true --include-query-string true --target-url "https://${ROOT_DOMAIN}" -o none
  echo "✅ Redirect created"
fi

echo ""
echo "== [6] Ensure HTTPS listeners for root and www =="
# Find existing frontend port 443
fp443="$(az network application-gateway frontend-port list -g "$RG" --gateway-name "$APPGW" --query "[?port==\`443\`].name|[0]" -o tsv)"
if [[ -z "${fp443:-}" ]]; then
  echo "❌ No frontend port 443 found on AppGW" >&2
  exit 1
fi

# Find SSL cert name already on AppGW (we will reuse if it matches; otherwise you must import cert colconnect.fr)
cert_name="$(az network application-gateway ssl-cert list -g "$RG" --gateway-name "$APPGW" --query "[0].name" -o tsv)"
if [[ -z "${cert_name:-}" ]]; then
  echo "❌ No SSL cert found on AppGW. Import colconnect.fr cert into KeyVault and attach to AppGW first." >&2
  exit 1
fi
echo "Using SSL cert on AppGW: $cert_name"

if az network application-gateway http-listener show -g "$RG" --gateway-name "$APPGW" -n "$LST_ROOT" >/dev/null 2>&1; then
  az_retry az network application-gateway http-listener update -g "$RG" --gateway-name "$APPGW" -n "$LST_ROOT" \
    --frontend-port "$fp443" --ssl-cert "$cert_name" --host-name "$ROOT_DOMAIN" -o none
else
  az_retry az network application-gateway http-listener create -g "$RG" --gateway-name "$APPGW" -n "$LST_ROOT" \
    --frontend-port "$fp443" --ssl-cert "$cert_name" --host-name "$ROOT_DOMAIN" -o none
fi
echo "✅ Listener root ready"

if az network application-gateway http-listener show -g "$RG" --gateway-name "$APPGW" -n "$LST_WWW" >/dev/null 2>&1; then
  az_retry az network application-gateway http-listener update -g "$RG" --gateway-name "$APPGW" -n "$LST_WWW" \
    --frontend-port "$fp443" --ssl-cert "$cert_name" --host-name "$WWW_DOMAIN" -o none
else
  az_retry az network application-gateway http-listener create -g "$RG" --gateway-name "$APPGW" -n "$LST_WWW" \
    --frontend-port "$fp443" --ssl-cert "$cert_name" --host-name "$WWW_DOMAIN" -o none
fi
echo "✅ Listener www ready"

echo ""
echo "== [7] Ensure rules =="
# Root rule -> backend storage
if az network application-gateway rule show -g "$RG" --gateway-name "$APPGW" -n "$RULE_ROOT" >/dev/null 2>&1; then
  az_retry az network application-gateway rule update -g "$RG" --gateway-name "$APPGW" -n "$RULE_ROOT" \
    --http-listener "$LST_ROOT" --rule-type Basic --address-pool "$BP" --http-settings "$BHS" -o none
else
  az_retry az network application-gateway rule create -g "$RG" --gateway-name "$APPGW" -n "$RULE_ROOT" \
    --http-listener "$LST_ROOT" --rule-type Basic --address-pool "$BP" --http-settings "$BHS" -o none
fi
echo "✅ Rule root -> storage ready"

# WWW rule -> redirect
if az network application-gateway rule show -g "$RG" --gateway-name "$APPGW" -n "$RULE_WWW" >/dev/null 2>&1; then
  az_retry az network application-gateway rule update -g "$RG" --gateway-name "$APPGW" -n "$RULE_WWW" \
    --http-listener "$LST_WWW" --rule-type Basic --redirect-config "$REDIR_WWW" -o none
else
  az_retry az network application-gateway rule create -g "$RG" --gateway-name "$APPGW" -n "$RULE_WWW" \
    --http-listener "$LST_WWW" --rule-type Basic --redirect-config "$REDIR_WWW" -o none
fi
echo "✅ Rule www -> redirect ready"

echo ""
echo "== [8] Verification (will work after DNS+cert are correct) =="
echo "DNS should point:"
echo "  A  ${ROOT_DOMAIN} -> AppGW public IP"
echo "  CNAME ${WWW_DOMAIN} -> ${ROOT_DOMAIN}"
echo ""
echo "Try:"
echo "  curl -sSI https://${ROOT_DOMAIN}/ | sed -n '1,12p'"
echo "  curl -sSI https://${WWW_DOMAIN}/ | sed -n '1,12p'"

echo ""
echo "== Rollback Git (1 step) =="
echo "git reset --hard HEAD~1"
echo "== Done =="
