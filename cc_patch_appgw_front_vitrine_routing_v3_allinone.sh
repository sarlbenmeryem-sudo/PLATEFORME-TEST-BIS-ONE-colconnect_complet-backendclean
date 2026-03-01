#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: AppGW vitrine routing (colconnect.fr + www) -> Storage static
# + /api/* redirect -> https://api.colconnect.fr
# ID: CC_PATCH_APPGW_FRONT_VITRINE_ROUTING_V3_ALLINONE_20260301
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
PATHRULE_FRONT="pr-front-default"

RULE_HTTP_ROOT="rule-http-root-redirect"
RULE_HTTP_WWW="rule-http-www-redirect"
RULE_HTTPS_ROOT="rule-https-root-pathmap"
RULE_HTTPS_WWW="rule-https-www-pathmap"

echo "== [CC_PATCH_APPGW_FRONT_VITRINE_ROUTING_V3_ALLINONE] Start =="
az account show -o none

echo "== Resolve Storage static website host =="
WEB_HOST="$(az storage account show -g "$RG" -n "$ST" --query "primaryEndpoints.web" -o tsv | sed 's|https://||; s|/||')"
if [[ -z "${WEB_HOST:-}" ]]; then
  echo "❌ Cannot resolve WEB_HOST for storage $ST" >&2
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi
echo "WEB_HOST=$WEB_HOST"

echo "== Ensure ssl-cert exists on AppGW: $SSL_CERT =="
az network application-gateway ssl-cert show -g "$RG" --gateway-name "$APPGW" -n "$SSL_CERT" -o none

echo "== Ensure frontend ports 80/443 =="
az network application-gateway frontend-port create -g "$RG" --gateway-name "$APPGW" -n fp-80  --port 80  -o none || true
az network application-gateway frontend-port create -g "$RG" --gateway-name "$APPGW" -n fp-443 --port 443 -o none || true

echo "== Resolve frontend IP config name =="
FEIP="$(az network application-gateway show -g "$RG" -n "$APPGW" --query "frontendIPConfigurations[0].name" -o tsv)"
if [[ -z "${FEIP:-}" ]]; then
  echo "❌ Cannot resolve frontendIPConfigurations[0].name" >&2
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi
echo "FEIP=$FEIP"

echo "== Upsert backend pool for Storage web host =="
az network application-gateway address-pool create \
  -g "$RG" --gateway-name "$APPGW" -n "$BP" \
  --servers "$WEB_HOST" -o none || true
az network application-gateway address-pool update \
  -g "$RG" --gateway-name "$APPGW" -n "$BP" \
  --servers "$WEB_HOST" -o none

echo "== Upsert probe for static site (/) with host=WEB_HOST =="
az network application-gateway probe create \
  -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
  --protocol Https \
  --host "$WEB_HOST" \
  --path "/" \
  --interval 30 \
  --timeout 30 \
  --threshold 3 \
  -o none || true
az network application-gateway probe update \
  -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
  --protocol Https \
  --host "$WEB_HOST" \
  --path "/" \
  --interval 30 \
  --timeout 30 \
  --threshold 3 \
  -o none

echo "== Upsert http-settings (HTTPS/443 + host header=WEB_HOST + probe) =="
az network application-gateway http-settings create \
  -g "$RG" --gateway-name "$APPGW" -n "$BHS" \
  --protocol Https --port 443 \
  --host-name "$WEB_HOST" \
  --timeout 30 \
  --pick-hostname-from-backend-address false \
  --probe "$PROBE" \
  -o none || true
az network application-gateway http-settings update \
  -g "$RG" --gateway-name "$APPGW" -n "$BHS" \
  --host-name "$WEB_HOST" \
  --pick-hostname-from-backend-address false \
  --timeout 30 \
  --probe "$PROBE" \
  -o none

echo "== Upsert HTTPS listeners (root + www) with correct cert =="
az network application-gateway http-listener create \
  -g "$RG" --gateway-name "$APPGW" -n "$L443_ROOT" \
  --frontend-ip "$FEIP" --frontend-port fp-443 \
  --ssl-cert "$SSL_CERT" \
  --host-name "$HOST_ROOT" \
  -o none || true
az network application-gateway http-listener update \
  -g "$RG" --gateway-name "$APPGW" -n "$L443_ROOT" \
  --ssl-cert "$SSL_CERT" \
  --host-name "$HOST_ROOT" \
  -o none

az network application-gateway http-listener create \
  -g "$RG" --gateway-name "$APPGW" -n "$L443_WWW" \
  --frontend-ip "$FEIP" --frontend-port fp-443 \
  --ssl-cert "$SSL_CERT" \
  --host-name "$HOST_WWW" \
  -o none || true
az network application-gateway http-listener update \
  -g "$RG" --gateway-name "$APPGW" -n "$L443_WWW" \
  --ssl-cert "$SSL_CERT" \
  --host-name "$HOST_WWW" \
  -o none

echo "== Upsert HTTP listeners (80) for redirect only =="
az network application-gateway http-listener create \
  -g "$RG" --gateway-name "$APPGW" -n "$L80_ROOT" \
  --frontend-ip "$FEIP" --frontend-port fp-80 \
  --host-name "$HOST_ROOT" \
  -o none || true
az network application-gateway http-listener update \
  -g "$RG" --gateway-name "$APPGW" -n "$L80_ROOT" \
  --host-name "$HOST_ROOT" \
  -o none

az network application-gateway http-listener create \
  -g "$RG" --gateway-name "$APPGW" -n "$L80_WWW" \
  --frontend-ip "$FEIP" --frontend-port fp-80 \
  --host-name "$HOST_WWW" \
  -o none || true
az network application-gateway http-listener update \
  -g "$RG" --gateway-name "$APPGW" -n "$L80_WWW" \
  --host-name "$HOST_WWW" \
  -o none

echo "== Redirect configs: http->https (root + www) =="
az network application-gateway redirect-config create \
  -g "$RG" --gateway-name "$APPGW" -n "$RS_REDIRECT_ROOT" \
  --type Permanent \
  --target-listener "$L443_ROOT" \
  --include-path true --include-query-string true \
  -o none || true
az network application-gateway redirect-config update \
  -g "$RG" --gateway-name "$APPGW" -n "$RS_REDIRECT_ROOT" \
  --type Permanent \
  --target-listener "$L443_ROOT" \
  --include-path true --include-query-string true \
  -o none

az network application-gateway redirect-config create \
  -g "$RG" --gateway-name "$APPGW" -n "$RS_REDIRECT_WWW" \
  --type Permanent \
  --target-listener "$L443_WWW" \
  --include-path true --include-query-string true \
  -o none || true
az network application-gateway redirect-config update \
  -g "$RG" --gateway-name "$APPGW" -n "$RS_REDIRECT_WWW" \
  --type Permanent \
  --target-listener "$L443_WWW" \
  --include-path true --include-query-string true \
  -o none

echo "== Redirect config for /api/* -> https://api.colconnect.fr (keep path+query) =="
az network application-gateway redirect-config create \
  -g "$RG" --gateway-name "$APPGW" -n "$RS_REDIRECT_API" \
  --type Permanent \
  --target-url "https://$API_HOST" \
  --include-path true --include-query-string true \
  -o none || true
az network application-gateway redirect-config update \
  -g "$RG" --gateway-name "$APPGW" -n "$RS_REDIRECT_API" \
  --type Permanent \
  --target-url "https://$API_HOST" \
  --include-path true --include-query-string true \
  -o none

echo "== Create/Update URL Path Map: default -> front, /api/* -> redirect =="
# create if missing
az network application-gateway url-path-map create \
  -g "$RG" --gateway-name "$APPGW" -n "$PATHMAP" \
  --default-address-pool "$BP" \
  --default-http-settings "$BHS" \
  --default-probe "$PROBE" \
  -o none || true

# ensure defaults are correct
az network application-gateway url-path-map update \
  -g "$RG" --gateway-name "$APPGW" -n "$PATHMAP" \
  --set defaultBackendAddressPool.id="$(az network application-gateway address-pool show -g "$RG" --gateway-name "$APPGW" -n "$BP" --query id -o tsv)" \
  --set defaultBackendHttpSettings.id="$(az network application-gateway http-settings show -g "$RG" --gateway-name "$APPGW" -n "$BHS" --query id -o tsv)" \
  -o none

# delete path-rule if exists then recreate (idempotent)
if az network application-gateway url-path-map rule show -g "$RG" --gateway-name "$APPGW" --path-map-name "$PATHMAP" -n "$PATHRULE_API" >/dev/null 2>&1; then
  az network application-gateway url-path-map rule delete -g "$RG" --gateway-name "$APPGW" --path-map-name "$PATHMAP" -n "$PATHRULE_API" -o none
fi

az network application-gateway url-path-map rule create \
  -g "$RG" --gateway-name "$APPGW" --path-map-name "$PATHMAP" -n "$PATHRULE_API" \
  --paths "/api/*" \
  --redirect-config "$RS_REDIRECT_API" \
  -o none

echo "== HTTP rules: 80 -> redirect to https =="
az network application-gateway rule create \
  -g "$RG" --gateway-name "$APPGW" -n "$RULE_HTTP_ROOT" \
  --rule-type Basic \
  --http-listener "$L80_ROOT" \
  --redirect-config "$RS_REDIRECT_ROOT" \
  --priority 101 \
  -o none || true
az network application-gateway rule update \
  -g "$RG" --gateway-name "$APPGW" -n "$RULE_HTTP_ROOT" \
  --redirect-config "$RS_REDIRECT_ROOT" \
  --priority 101 \
  -o none

az network application-gateway rule create \
  -g "$RG" --gateway-name "$APPGW" -n "$RULE_HTTP_WWW" \
  --rule-type Basic \
  --http-listener "$L80_WWW" \
  --redirect-config "$RS_REDIRECT_WWW" \
  --priority 102 \
  -o none || true
az network application-gateway rule update \
  -g "$RG" --gateway-name "$APPGW" -n "$RULE_HTTP_WWW" \
  --redirect-config "$RS_REDIRECT_WWW" \
  --priority 102 \
  -o none

echo "== HTTPS rules: path-based routing via url-path-map (root + www) =="
az network application-gateway rule create \
  -g "$RG" --gateway-name "$APPGW" -n "$RULE_HTTPS_ROOT" \
  --rule-type PathBasedRouting \
  --http-listener "$L443_ROOT" \
  --url-path-map "$PATHMAP" \
  --priority 201 \
  -o none || true
az network application-gateway rule update \
  -g "$RG" --gateway-name "$APPGW" -n "$RULE_HTTPS_ROOT" \
  --url-path-map "$PATHMAP" \
  --priority 201 \
  -o none

az network application-gateway rule create \
  -g "$RG" --gateway-name "$APPGW" -n "$RULE_HTTPS_WWW" \
  --rule-type PathBasedRouting \
  --http-listener "$L443_WWW" \
  --url-path-map "$PATHMAP" \
  --priority 202 \
  -o none || true
az network application-gateway rule update \
  -g "$RG" --gateway-name "$APPGW" -n "$RULE_HTTPS_WWW" \
  --url-path-map "$PATHMAP" \
  --priority 202 \
  -o none

echo "== Verify listeners & rules =="
az network application-gateway rule list -g "$RG" --gateway-name "$APPGW" --query "[].{name:name,priority:priority,ruleType:ruleType}" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
