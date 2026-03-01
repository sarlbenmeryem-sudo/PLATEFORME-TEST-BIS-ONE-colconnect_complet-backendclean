#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Fix URL path-map creation + enforce routing rules (front + /api redirect)
# ID: CC_PATCH_APPGW_FRONT_VITRINE_ROUTING_V6_FIX_PATHMAP_CREATE_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"
ST="stcolconnectfrontfrc01"

SSL_CERT="ssl-colconnect-root-www"

HOST_ROOT="colconnect.fr"
HOST_WWW="www.colconnect.fr"
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

echo "== [CC_PATCH_APPGW_FRONT_VITRINE_ROUTING_V6_FIX_PATHMAP_CREATE] Start =="
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

echo "== Resolve existing frontend port names for 80/443 (reuse) =="
FP80="$(az network application-gateway show -g "$RG" -n "$APPGW" --query "frontendPorts[?port==\`80\`].name | [0]" -o tsv)"
FP443="$(az network application-gateway show -g "$RG" -n "$APPGW" --query "frontendPorts[?port==\`443\`].name | [0]" -o tsv)"
if [[ -z "${FP80:-}" || -z "${FP443:-}" ]]; then
  echo "❌ Cannot find existing frontendPorts for 80/443" >&2
  az network application-gateway show -g "$RG" -n "$APPGW" --query "frontendPorts[].{name:name,port:port}" -o table || true
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi
echo "FP80=$FP80"
echo "FP443=$FP443"

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

echo "== Ensure URL path map exists (CREATE requires --paths) =="
if az network application-gateway url-path-map show -g "$RG" --gateway-name "$APPGW" -n "$PATHMAP" >/dev/null 2>&1; then
  echo "✅ Path map exists: $PATHMAP (updating defaults)"
  az network application-gateway url-path-map update \
    -g "$RG" --gateway-name "$APPGW" -n "$PATHMAP" \
    --default-address-pool "$BP" \
    --default-http-settings "$BHS" \
    --default-probe "$PROBE" \
    -o none
else
  echo "Creating path map $PATHMAP with initial /api/* rule (required by CLI)"
  az network application-gateway url-path-map create \
    -g "$RG" --gateway-name "$APPGW" -n "$PATHMAP" \
    --default-address-pool "$BP" \
    --default-http-settings "$BHS" \
    --default-probe "$PROBE" \
    --rule-name "$PATHRULE_API" \
    --paths "/api/*" \
    --redirect-config "$RS_REDIRECT_API" \
    -o none
fi

echo "== Ensure /api/* rule exists and points to redirect-config =="
if az network application-gateway url-path-map rule show -g "$RG" --gateway-name "$APPGW" --path-map-name "$PATHMAP" -n "$PATHRULE_API" >/dev/null 2>&1; then
  az network application-gateway url-path-map rule delete \
    -g "$RG" --gateway-name "$APPGW" --path-map-name "$PATHMAP" -n "$PATHRULE_API" -o none
fi
az network application-gateway url-path-map rule create \
  -g "$RG" --gateway-name "$APPGW" --path-map-name "$PATHMAP" -n "$PATHRULE_API" \
  --paths "/api/*" \
  --redirect-config "$RS_REDIRECT_API" \
  -o none

ensure_rule_redirect () {
  local want_rule="$1"; local listener="$2"; local redirect="$3"; local prio="$4"
  local existing
  existing="$(az network application-gateway show -g "$RG" -n "$APPGW" --query "requestRoutingRules[?contains(httpListener.id,'/httpListeners/$listener')].name | [0]" -o tsv)"
  if [[ -n "${existing:-}" && "${existing}" != "None" ]]; then
    az network application-gateway rule update \
      -g "$RG" --gateway-name "$APPGW" -n "$existing" \
      --redirect-config "$redirect" \
      --priority "$prio" \
      -o none
  else
    az network application-gateway rule create \
      -g "$RG" --gateway-name "$APPGW" -n "$want_rule" \
      --rule-type Basic \
      --http-listener "$listener" \
      --redirect-config "$redirect" \
      --priority "$prio" \
      -o none
  fi
}

ensure_rule_pathmap () {
  local want_rule="$1"; local listener="$2"; local pathmap="$3"; local prio="$4"
  local existing
  existing="$(az network application-gateway show -g "$RG" -n "$APPGW" --query "requestRoutingRules[?contains(httpListener.id,'/httpListeners/$listener')].name | [0]" -o tsv)"
  if [[ -n "${existing:-}" && "${existing}" != "None" ]]; then
    az network application-gateway rule update \
      -g "$RG" --gateway-name "$APPGW" -n "$existing" \
      --rule-type PathBasedRouting \
      --url-path-map "$pathmap" \
      --priority "$prio" \
      -o none
  else
    az network application-gateway rule create \
      -g "$RG" --gateway-name "$APPGW" -n "$want_rule" \
      --rule-type PathBasedRouting \
      --http-listener "$listener" \
      --url-path-map "$pathmap" \
      --priority "$prio" \
      -o none
  fi
}

echo "== Rules: HTTP -> HTTPS =="
ensure_rule_redirect "$RULE_HTTP_ROOT" "$L80_ROOT" "$RS_REDIRECT_ROOT" "$P_HTTP_ROOT"
ensure_rule_redirect "$RULE_HTTP_WWW"  "$L80_WWW"  "$RS_REDIRECT_WWW"  "$P_HTTP_WWW"

echo "== Rules: HTTPS -> PathBasedRouting (front + /api redirect) =="
ensure_rule_pathmap "$RULE_HTTPS_ROOT" "$L443_ROOT" "$PATHMAP" "$P_HTTPS_ROOT"
ensure_rule_pathmap "$RULE_HTTPS_WWW"  "$L443_WWW"  "$PATHMAP" "$P_HTTPS_WWW"

echo "== Verify rules (name/priority/type) =="
az network application-gateway rule list -g "$RG" --gateway-name "$APPGW" --query "[].{name:name,priority:priority,ruleType:ruleType}" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
