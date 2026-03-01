#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: AppGW vitrine routing (colconnect.fr + www) -> Storage static, /api/* redirect to api.colconnect.fr
# ID: CC_PATCH_APPGW_FRONT_VITRINE_ROUTING_V1_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

# Must match Patch 1 storage name
ST="stcolconnectfrontfrc01"

SSL_CERT="ssl-colconnect-root-www"

HOST_ROOT="colconnect.fr"
HOST_WWW="www.colconnect.fr"
API_HOST="api.colconnect.fr"

# Names
BP="bp-front-static"
BHS="bhs-front-https"
PROBE="probe-front"
LISTENER_ROOT="lis-https-root"
LISTENER_WWW="lis-https-www"
URLPATHMAP="pm-front"
PATHRULE_API="pr-api-redirect"
REDIR_API="rd-to-api"
RULE_ROOT="rule-https-root-front"
RULE_WWW="rule-https-www-front"

echo "== [CC_PATCH_APPGW_FRONT_VITRINE_ROUTING_V1] Start =="

az account show -o none

echo "== Resolve Storage static website host =="
WEB_HOST="$(az storage account show -g "$RG" -n "$ST" --query "primaryEndpoints.web" -o tsv | sed 's#https\?://##' | sed 's#/$##')"
if [[ -z "${WEB_HOST:-}" ]]; then
  echo "❌ Cannot resolve storage web host" >&2
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi
echo "WEB_HOST=$WEB_HOST"

echo "== Ensure ssl-cert exists on AppGW: $SSL_CERT =="
az network application-gateway ssl-cert show -g "$RG" --gateway-name "$APPGW" -n "$SSL_CERT" -o none

echo "== Upsert backend pool for Storage web host =="
# Backend addresses accept FQDN
if az network application-gateway address-pool show -g "$RG" --gateway-name "$APPGW" -n "$BP" >/dev/null 2>&1; then
  az network application-gateway address-pool update \
    -g "$RG" --gateway-name "$APPGW" -n "$BP" \
    --servers "$WEB_HOST" \
    -o none
else
  az network application-gateway address-pool create \
    -g "$RG" --gateway-name "$APPGW" -n "$BP" \
    --servers "$WEB_HOST" \
    -o none
fi

echo "== Upsert http-settings (HTTPS/443 + host header=WEB_HOST) =="
if az network application-gateway http-settings show -g "$RG" --gateway-name "$APPGW" -n "$BHS" >/dev/null 2>&1; then
  az network application-gateway http-settings update \
    -g "$RG" --gateway-name "$APPGW" -n "$BHS" \
    --protocol Https --port 443 \
    --host-name "$WEB_HOST" \
    --host-name-from-backend-pool false \
    --timeout 30 \
    -o none
else
  az network application-gateway http-settings create \
    -g "$RG" --gateway-name "$APPGW" -n "$BHS" \
    --protocol Https --port 443 \
    --host-name "$WEB_HOST" \
    --timeout 30 \
    -o none
fi

echo "== Upsert probe for static site (/) =="
if az network application-gateway probe show -g "$RG" --gateway-name "$APPGW" -n "$PROBE" >/dev/null 2>&1; then
  az network application-gateway probe update \
    -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
    --protocol Https \
    --path "/" \
    --interval 30 \
    --timeout 10 \
    -o none
else
  az network application-gateway probe create \
    -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
    --protocol Https \
    --path "/" \
    --interval 30 \
    --timeout 10 \
    -o none
fi

echo "== Attach probe to http-settings =="
az network application-gateway http-settings update \
  -g "$RG" --gateway-name "$APPGW" -n "$BHS" \
  --probe "$PROBE" \
  -o none

echo "== Ensure HTTPS listeners for root + www =="
# We reuse existing frontend-port 443; just create listeners with host-names.

if az network application-gateway http-listener show -g "$RG" --gateway-name "$APPGW" -n "$LISTENER_ROOT" >/dev/null 2>&1; then
  az network application-gateway http-listener update \
    -g "$RG" --gateway-name "$APPGW" -n "$LISTENER_ROOT" \
    --host-name "$HOST_ROOT" \
    --ssl-cert "$SSL_CERT" \
    -o none
else
  az network application-gateway http-listener create \
    -g "$RG" --gateway-name "$APPGW" -n "$LISTENER_ROOT" \
    --frontend-ip appGatewayFrontendIP \
    --frontend-port appGatewayFrontendPort \
    --host-name "$HOST_ROOT" \
    --ssl-cert "$SSL_CERT" \
    -o none
fi

if az network application-gateway http-listener show -g "$RG" --gateway-name "$APPGW" -n "$LISTENER_WWW" >/dev/null 2>&1; then
  az network application-gateway http-listener update \
    -g "$RG" --gateway-name "$APPGW" -n "$LISTENER_WWW" \
    --host-name "$HOST_WWW" \
    --ssl-cert "$SSL_CERT" \
    -o none
else
  az network application-gateway http-listener create \
    -g "$RG" --gateway-name "$APPGW" -n "$LISTENER_WWW" \
    --frontend-ip appGatewayFrontendIP \
    --frontend-port appGatewayFrontendPort \
    --host-name "$HOST_WWW" \
    --ssl-cert "$SSL_CERT" \
    -o none
fi

echo "== Create redirect /api/* -> https://api.colconnect.fr (keep path+query) =="
if az network application-gateway redirect-config show -g "$RG" --gateway-name "$APPGW" -n "$REDIR_API" >/dev/null 2>&1; then
  az network application-gateway redirect-config update \
    -g "$RG" --gateway-name "$APPGW" -n "$REDIR_API" \
    --target-url "https://$API_HOST" \
    --include-path true \
    --include-query-string true \
    --type Permanent \
    -o none
else
  az network application-gateway redirect-config create \
    -g "$RG" --gateway-name "$APPGW" -n "$REDIR_API" \
    --target-url "https://$API_HOST" \
    --include-path true \
    --include-query-string true \
    --type Permanent \
    -o none
fi

echo "== Create/Update URL path map: default -> static, /api/* -> redirect =="
# URL path map requires default backend + settings, plus path-rules.
if az network application-gateway url-path-map show -g "$RG" --gateway-name "$APPGW" -n "$URLPATHMAP" >/dev/null 2>&1; then
  az network application-gateway url-path-map update \
    -g "$RG" --gateway-name "$APPGW" -n "$URLPATHMAP" \
    --default-address-pool "$BP" \
    --default-http-settings "$BHS" \
    -o none
else
  az network application-gateway url-path-map create \
    -g "$RG" --gateway-name "$APPGW" -n "$URLPATHMAP" \
    --default-address-pool "$BP" \
    --default-http-settings "$BHS" \
    -o none
fi

# Ensure path-rule for /api/*
if az network application-gateway url-path-map rule show -g "$RG" --gateway-name "$APPGW" --path-map-name "$URLPATHMAP" -n "$PATHRULE_API" >/dev/null 2>&1; then
  az network application-gateway url-path-map rule update \
    -g "$RG" --gateway-name "$APPGW" --path-map-name "$URLPATHMAP" -n "$PATHRULE_API" \
    --paths "/api/*" \
    --redirect-config "$REDIR_API" \
    -o none
else
  az network application-gateway url-path-map rule create \
    -g "$RG" --gateway-name "$APPGW" --path-map-name "$URLPATHMAP" -n "$PATHRULE_API" \
    --paths "/api/*" \
    --redirect-config "$REDIR_API" \
    -o none
fi

echo "== Create/Update routing rules for root + www =="
# Each listener needs a request-routing-rule pointing to url-path-map
if az network application-gateway rule show -g "$RG" --gateway-name "$APPGW" -n "$RULE_ROOT" >/dev/null 2>&1; then
  az network application-gateway rule update \
    -g "$RG" --gateway-name "$APPGW" -n "$RULE_ROOT" \
    --http-listener "$LISTENER_ROOT" \
    --rule-type PathBasedRouting \
    --url-path-map "$URLPATHMAP" \
    -o none
else
  az network application-gateway rule create \
    -g "$RG" --gateway-name "$APPGW" -n "$RULE_ROOT" \
    --http-listener "$LISTENER_ROOT" \
    --rule-type PathBasedRouting \
    --url-path-map "$URLPATHMAP" \
    --priority 200 \
    -o none
fi

if az network application-gateway rule show -g "$RG" --gateway-name "$APPGW" -n "$RULE_WWW" >/dev/null 2>&1; then
  az network application-gateway rule update \
    -g "$RG" --gateway-name "$APPGW" -n "$RULE_WWW" \
    --http-listener "$LISTENER_WWW" \
    --rule-type PathBasedRouting \
    --url-path-map "$URLPATHMAP" \
    -o none
else
  az network application-gateway rule create \
    -g "$RG" --gateway-name "$APPGW" -n "$RULE_WWW" \
    --http-listener "$LISTENER_WWW" \
    --rule-type PathBasedRouting \
    --url-path-map "$URLPATHMAP" \
    --priority 210 \
    -o none
fi

echo ""
echo "✅ Vitrine routing configured:"
echo "  - https://colconnect.fr -> Storage static (via AppGW/WAF)"
echo "  - https://www.colconnect.fr -> Storage static (via AppGW/WAF)"
echo "  - https://colconnect.fr/api/* -> redirect https://api.colconnect.fr/api/*"

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
