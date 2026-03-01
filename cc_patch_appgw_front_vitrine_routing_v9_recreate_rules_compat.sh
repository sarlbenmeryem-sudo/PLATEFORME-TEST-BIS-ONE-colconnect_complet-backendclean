#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Front vitrine routing - recreate routing rules (CLI compat)
# - HTTP -> HTTPS redirect
# - HTTPS -> PathBasedRouting using url-path-map (default front + /api redirect)
# ID: CC_PATCH_APPGW_FRONT_VITRINE_ROUTING_V9_RECREATE_RULES_COMPAT_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"
ST="stcolconnectfrontfrc01"

SSL_CERT="ssl-colconnect-root-www"
API_HOST="api.colconnect.fr"

BP="bp-front-static"
BHS="bhs-front-https"
PROBE="probe-front"

L80_ROOT="lis-http-root"
L80_WWW="lis-http-www"
L443_ROOT="lis-https-root"
L443_WWW="lis-https-www"

RS_REDIRECT_ROOT="rs-redirect-root-https"
RS_REDIRECT_WWW="rs-redirect-www-https"
RS_REDIRECT_API="rs-redirect-api-to-api-host"

PATHMAP="pm-front"
PATHRULE_API="pr-api-redirect"

RULE_HTTP_ROOT="rule-http-root"
RULE_HTTP_WWW="rule-http-www"
RULE_HTTPS_ROOT="rule-https-root"
RULE_HTTPS_WWW="rule-https-www"

P_HTTP_ROOT="101"
P_HTTP_WWW="102"
P_HTTPS_ROOT="201"
P_HTTPS_WWW="202"

echo "== [CC_PATCH_APPGW_FRONT_VITRINE_ROUTING_V9_RECREATE_RULES_COMPAT] Start =="
az account show -o none

echo "== Resolve WEB_HOST from Storage static endpoint =="
WEB_HOST="$(az storage account show -g "$RG" -n "$ST" --query "primaryEndpoints.web" -o tsv | sed 's|https://||; s|/||')"
if [[ -z "${WEB_HOST:-}" ]]; then
  echo "❌ Cannot resolve WEB_HOST for storage $ST" >&2
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi
echo "WEB_HOST=$WEB_HOST"

echo "== Ensure ssl-cert exists on AppGW: $SSL_CERT =="
az network application-gateway ssl-cert show -g "$RG" --gateway-name "$APPGW" -n "$SSL_CERT" -o none

echo "== Ensure backend pool for Storage web host =="
az network application-gateway address-pool create \
  -g "$RG" --gateway-name "$APPGW" -n "$BP" \
  --servers "$WEB_HOST" -o none || true
az network application-gateway address-pool update \
  -g "$RG" --gateway-name "$APPGW" -n "$BP" \
  --servers "$WEB_HOST" -o none

echo "== Ensure probe-front (Https + host=WEB_HOST + /) =="
az network application-gateway probe create \
  -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
  --protocol Https --host "$WEB_HOST" --path "/" \
  --interval 30 --timeout 30 --threshold 3 \
  -o none || true
az network application-gateway probe update \
  -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
  --protocol Https --host "$WEB_HOST" --path "/" \
  --interval 30 --timeout 30 --threshold 3 \
  -o none

echo "== Ensure http-settings front (Https/443 + host header=WEB_HOST + probe) =="
az network application-gateway http-settings create \
  -g "$RG" --gateway-name "$APPGW" -n "$BHS" \
  --protocol Https --port 443 \
  --host-name "$WEB_HOST" \
  --host-name-from-backend-pool false \
  --timeout 30 \
  --probe "$PROBE" \
  -o none || true
az network application-gateway http-settings update \
  -g "$RG" --gateway-name "$APPGW" -n "$BHS" \
  --host-name "$WEB_HOST" \
  --host-name-from-backend-pool false \
  --timeout 30 \
  --probe "$PROBE" \
  -o none

echo "== Ensure redirect configs =="
az network application-gateway redirect-config create \
  -g "$RG" --gateway-name "$APPGW" -n "$RS_REDIRECT_ROOT" \
  --type Permanent --target-listener "$L443_ROOT" \
  --include-path true --include-query-string true -o none || true
az network application-gateway redirect-config update \
  -g "$RG" --gateway-name "$APPGW" -n "$RS_REDIRECT_ROOT" \
  --type Permanent --target-listener "$L443_ROOT" \
  --include-path true --include-query-string true -o none

az network application-gateway redirect-config create \
  -g "$RG" --gateway-name "$APPGW" -n "$RS_REDIRECT_WWW" \
  --type Permanent --target-listener "$L443_WWW" \
  --include-path true --include-query-string true -o none || true
az network application-gateway redirect-config update \
  -g "$RG" --gateway-name "$APPGW" -n "$RS_REDIRECT_WWW" \
  --type Permanent --target-listener "$L443_WWW" \
  --include-path true --include-query-string true -o none

az network application-gateway redirect-config create \
  -g "$RG" --gateway-name "$APPGW" -n "$RS_REDIRECT_API" \
  --type Permanent --target-url "https://$API_HOST" \
  --include-path true --include-query-string true -o none || true
az network application-gateway redirect-config update \
  -g "$RG" --gateway-name "$APPGW" -n "$RS_REDIRECT_API" \
  --type Permanent --target-url "https://$API_HOST" \
  --include-path true --include-query-string true -o none

echo "== Ensure path map exists (default front + /api/* redirect) =="
if az network application-gateway url-path-map show -g "$RG" --gateway-name "$APPGW" -n "$PATHMAP" >/dev/null 2>&1; then
  echo "ℹ️ Path map exists: $PATHMAP"
else
  az network application-gateway url-path-map create \
    -g "$RG" --gateway-name "$APPGW" -n "$PATHMAP" \
    --default-address-pool "$BP" \
    --default-http-settings "$BHS" \
    --rule-name "$PATHRULE_API" \
    --paths "/api/*" \
    --redirect-config "$RS_REDIRECT_API" \
    -o none
fi

echo "== Helper: delete ALL rules bound to a listener (safe) =="
delete_rules_by_listener () {
  local listener="$1"
  local names
  names="$(az network application-gateway show -g "$RG" -n "$APPGW" \
    --query "requestRoutingRules[?contains(httpListener.id,'/httpListeners/$listener')].name" -o tsv || true)"
  if [[ -n "${names:-}" ]]; then
    for r in $names; do
      echo "ℹ️ Deleting rule bound to $listener: $r"
      az network application-gateway rule delete -g "$RG" --gateway-name "$APPGW" -n "$r" -o none || true
    done
  fi
}

echo "== Recreate HTTP redirect rules =="
delete_rules_by_listener "$L80_ROOT"
az network application-gateway rule create \
  -g "$RG" --gateway-name "$APPGW" -n "$RULE_HTTP_ROOT" \
  --rule-type Basic \
  --http-listener "$L80_ROOT" \
  --redirect-config "$RS_REDIRECT_ROOT" \
  --priority "$P_HTTP_ROOT" \
  -o none

delete_rules_by_listener "$L80_WWW"
az network application-gateway rule create \
  -g "$RG" --gateway-name "$APPGW" -n "$RULE_HTTP_WWW" \
  --rule-type Basic \
  --http-listener "$L80_WWW" \
  --redirect-config "$RS_REDIRECT_WWW" \
  --priority "$P_HTTP_WWW" \
  -o none

echo "== Recreate HTTPS path-based rules (CLI compat: specify --address-pool and --http-settings explicitly) =="

delete_rules_by_listener "$L443_ROOT"
az network application-gateway rule create \
  -g "$RG" --gateway-name "$APPGW" -n "$RULE_HTTPS_ROOT" \
  --rule-type PathBasedRouting \
  --http-listener "$L443_ROOT" \
  --url-path-map "$PATHMAP" \
  --address-pool "$BP" \
  --http-settings "$BHS" \
  --priority "$P_HTTPS_ROOT" \
  -o none

delete_rules_by_listener "$L443_WWW"
az network application-gateway rule create \
  -g "$RG" --gateway-name "$APPGW" -n "$RULE_HTTPS_WWW" \
  --rule-type PathBasedRouting \
  --http-listener "$L443_WWW" \
  --url-path-map "$PATHMAP" \
  --address-pool "$BP" \
  --http-settings "$BHS" \
  --priority "$P_HTTPS_WWW" \
  -o none

echo "== Verify routing rules =="
az network application-gateway rule list -g "$RG" --gateway-name "$APPGW" \
  --query "[].{name:name,priority:priority,ruleType:ruleType,listener:httpListener.id}" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
