#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: AppGW vitrine routing (compat CLI + reuse existing ports/listeners)
# ID: CC_PATCH_APPGW_FRONT_VITRINE_ROUTING_V4_COMPAT_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"
ST="stcolconnectfrontfrc01"

SSL_CERT="ssl-colconnect-root-www"

HOST_ROOT="colconnect.fr"
HOST_WWW="www.colconnect.fr"
API_HOST="api.colconnect.fr"

# Objects we manage (names stable)
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

echo "== [CC_PATCH_APPGW_FRONT_VITRINE_ROUTING_V4_COMPAT] Start =="
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

echo "== Resolve FEIP name =="
FEIP="$(az network application-gateway show -g "$RG" -n "$APPGW" --query "frontendIPConfigurations[0].name" -o tsv)"
if [[ -z "${FEIP:-}" ]]; then
  echo "❌ Cannot resolve frontendIPConfigurations[0].name" >&2
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi
echo "FEIP=$FEIP"

echo "== Resolve existing frontend port names for 80/443 (reuse, no create) =="
FP80="$(az network application-gateway show -g "$RG" -n "$APPGW" --query "frontendPorts[?port==\`80\`].name | [0]" -o tsv)"
FP443="$(az network application-gateway show -g "$RG" -n "$APPGW" --query "frontendPorts[?port==\`443\`].name | [0]" -o tsv)"
if [[ -z "${FP80:-}" || -z "${FP443:-}" ]]; then
  echo "❌ Cannot find existing frontendPorts for 80/443 on AppGW" >&2
  az network application-gateway show -g "$RG" -n "$APPGW" --query "frontendPorts[].{name:name,port:port}" -o table || true
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi
echo "FP80=$FP80"
echo "FP443=$FP443"

echo "== Upsert backend pool for Storage web host =="
az network application-gateway address-pool create \
  -g "$RG" --gateway-name "$APPGW" -n "$BP" \
  --servers "$WEB_HOST" -o none || true
az network application-gateway address-pool update \
  -g "$RG" --gateway-name "$APPGW" -n "$BP" \
  --servers "$WEB_HOST" -o none

echo "== Upsert probe-front (Https + host=WEB_HOST + /) =="
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

echo "== Upsert http-settings front (Https/443 + host header=WEB_HOST + host-from-backend-pool false + probe) =="
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

# -------- listeners: create if missing, update if exists --------
ensure_listener () {
  local want_name="$1"
  local port_name="$2"
  local host_name="$3"
  local ssl_cert="${4:-}"   # empty for HTTP

  local existing
  existing="$(az network application-gateway show -g "$RG" -n "$APPGW" --query "httpListeners[?hostName=='$host_name' && contains(frontendPort.id,'/frontendPorts/$port_name')].name | [0]" -o tsv)"
  if [[ -n "${existing:-}" && "${existing}" != "None" ]]; then
    echo "Listener exists for $host_name:$port_name -> $existing (updating)"
    if [[ -n "${ssl_cert:-}" ]]; then
      az network application-gateway http-listener update \
        -g "$RG" --gateway-name "$APPGW" -n "$existing" \
        --ssl-cert "$ssl_cert" \
        --host-name "$host_name" \
        -o none
    else
      az network application-gateway http-listener update \
        -g "$RG" --gateway-name "$APPGW" -n "$existing" \
        --host-name "$host_name" \
        -o none
    fi
    echo "$existing"
    return 0
  fi

  echo "Creating listener $want_name for $host_name:$port_name"
  if [[ -n "${ssl_cert:-}" ]]; then
    az network application-gateway http-listener create \
      -g "$RG" --gateway-name "$APPGW" -n "$want_name" \
      --frontend-ip "$FEIP" --frontend-port "$port_name" \
      --ssl-cert "$ssl_cert" \
      --host-name "$host_name" \
      -o none
  else
    az network application-gateway http-listener create \
      -g "$RG" --gateway-name "$APPGW" -n "$want_name" \
      --frontend-ip "$FEIP" --frontend-port "$port_name" \
      --host-name "$host_name" \
      -o none
  fi
  echo "$want_name"
}

echo "== Ensure listeners =="
ACT_L80_ROOT="$(ensure_listener "$L80_ROOT" "$FP80"  "$HOST_ROOT")"
ACT_L80_WWW="$(ensure_listener "$L80_WWW" "$FP80"  "$HOST_WWW")"
ACT_L443_ROOT="$(ensure_listener "$L443_ROOT" "$FP443" "$HOST_ROOT" "$SSL_CERT")"
ACT_L443_WWW="$(ensure_listener "$L443_WWW" "$FP443" "$HOST_WWW" "$SSL_CERT")"

echo "== Redirect configs =="
az network application-gateway redirect-config create \
  -g "$RG" --gateway-name "$APPGW" -n "$RS_REDIRECT_ROOT" \
  --type Permanent --target-listener "$ACT_L443_ROOT" \
  --include-path true --include-query-string true -o none || true
az network application-gateway redirect-config update \
  -g "$RG" --gateway-name "$APPGW" -n "$RS_REDIRECT_ROOT" \
  --type Permanent --target-listener "$ACT_L443_ROOT" \
  --include-path true --include-query-string true -o none

az network application-gateway redirect-config create \
  -g "$RG" --gateway-name "$APPGW" -n "$RS_REDIRECT_WWW" \
  --type Permanent --target-listener "$ACT_L443_WWW" \
  --include-path true --include-query-string true -o none || true
az network application-gateway redirect-config update \
  -g "$RG" --gateway-name "$APPGW" -n "$RS_REDIRECT_WWW" \
  --type Permanent --target-listener "$ACT_L443_WWW" \
  --include-path true --include-query-string true -o none

az network application-gateway redirect-config create \
  -g "$RG" --gateway-name "$APPGW" -n "$RS_REDIRECT_API" \
  --type Permanent --target-url "https://$API_HOST" \
  --include-path true --include-query-string true -o none || true
az network application-gateway redirect-config update \
  -g "$RG" --gateway-name "$APPGW" -n "$RS_REDIRECT_API" \
  --type Permanent --target-url "https://$API_HOST" \
  --include-path true --include-query-string true -o none

echo "== URL Path Map (default->front, /api/* -> redirect api host) =="
az network application-gateway url-path-map create \
  -g "$RG" --gateway-name "$APPGW" -n "$PATHMAP" \
  --default-address-pool "$BP" \
  --default-http-settings "$BHS" \
  --default-probe "$PROBE" \
  -o none || true

# Ensure /api/* rule exists (delete+recreate to be safe)
if az network application-gateway url-path-map rule show -g "$RG" --gateway-name "$APPGW" --path-map-name "$PATHMAP" -n "$PATHRULE_API" >/dev/null 2>&1; then
  az network application-gateway url-path-map rule delete -g "$RG" --gateway-name "$APPGW" --path-map-name "$PATHMAP" -n "$PATHRULE_API" -o none
fi
az network application-gateway url-path-map rule create \
  -g "$RG" --gateway-name "$APPGW" --path-map-name "$PATHMAP" -n "$PATHRULE_API" \
  --paths "/api/*" \
  --redirect-config "$RS_REDIRECT_API" \
  -o none

# -------- rules: one rule per listener -> update if exists, else create --------
ensure_rule_redirect () {
  local want_rule="$1"
  local listener="$2"
  local redirect="$3"
  local prio="$4"

  local existing
  existing="$(az network application-gateway show -g "$RG" -n "$APPGW" --query "requestRoutingRules[?contains(httpListener.id,'/httpListeners/$listener')].name | [0]" -o tsv)"
  if [[ -n "${existing:-}" && "${existing}" != "None" ]]; then
    echo "Updating existing rule on listener $listener -> $existing (redirect=$redirect)"
    az network application-gateway rule update \
      -g "$RG" --gateway-name "$APPGW" -n "$existing" \
      --redirect-config "$redirect" \
      --priority "$prio" \
      -o none
    return 0
  fi

  echo "Creating rule $want_rule on listener $listener (redirect=$redirect)"
  az network application-gateway rule create \
    -g "$RG" --gateway-name "$APPGW" -n "$want_rule" \
    --rule-type Basic \
    --http-listener "$listener" \
    --redirect-config "$redirect" \
    --priority "$prio" \
    -o none
}

ensure_rule_pathmap () {
  local want_rule="$1"
  local listener="$2"
  local pathmap="$3"
  local prio="$4"

  local existing
  existing="$(az network application-gateway show -g "$RG" -n "$APPGW" --query "requestRoutingRules[?contains(httpListener.id,'/httpListeners/$listener')].name | [0]" -o tsv)"
  if [[ -n "${existing:-}" && "${existing}" != "None" ]]; then
    echo "Updating existing rule on listener $listener -> $existing (pathmap=$pathmap)"
    az network application-gateway rule update \
      -g "$RG" --gateway-name "$APPGW" -n "$existing" \
      --rule-type PathBasedRouting \
      --url-path-map "$pathmap" \
      --priority "$prio" \
      -o none
    return 0
  fi

  echo "Creating rule $want_rule on listener $listener (pathmap=$pathmap)"
  az network application-gateway rule create \
    -g "$RG" --gateway-name "$APPGW" -n "$want_rule" \
    --rule-type PathBasedRouting \
    --http-listener "$listener" \
    --url-path-map "$pathmap" \
    --priority "$prio" \
    -o none
}

echo "== Rules: HTTP->HTTPS redirects =="
ensure_rule_redirect "$RULE_HTTP_ROOT" "$ACT_L80_ROOT" "$RS_REDIRECT_ROOT" "$P_HTTP_ROOT"
ensure_rule_redirect "$RULE_HTTP_WWW"  "$ACT_L80_WWW"  "$RS_REDIRECT_WWW"  "$P_HTTP_WWW"

echo "== Rules: HTTPS path-based -> vitrine + /api/* redirect =="
ensure_rule_pathmap "$RULE_HTTPS_ROOT" "$ACT_L443_ROOT" "$PATHMAP" "$P_HTTPS_ROOT"
ensure_rule_pathmap "$RULE_HTTPS_WWW"  "$ACT_L443_WWW"  "$PATHMAP" "$P_HTTPS_WWW"

echo "== Verify rules =="
az network application-gateway rule list -g "$RG" --gateway-name "$APPGW" --query "[].{name:name,priority:priority,ruleType:ruleType}" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
