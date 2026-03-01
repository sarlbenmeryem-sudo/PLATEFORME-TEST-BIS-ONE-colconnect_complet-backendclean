#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

PFX_PATH="${1:-}"
PFX_PASSWORD="${2:-}"
if [[ -z "${PFX_PATH:-}" || -z "${PFX_PASSWORD:-}" ]]; then
  echo "Usage: $0 /path/to/cert.pfx 'PFX_PASSWORD'" >&2
  exit 2
fi
if [[ ! -f "$PFX_PATH" ]]; then
  echo "❌ PFX not found: $PFX_PATH" >&2
  exit 2
fi

# Noms
CERT_NAME="cc-cert-pfx"
FEPORT_443_NAME="feport-443"
LISTENER_HTTPS="listener-https-443"
RULE_HTTPS="rule-https"
REDIRECT_NAME="redir-http-to-https"

# Existants chez toi
HTTP_RULE="rule1"
URLPATHMAP="upm-colconnect"   # déjà vu dans ton dump

echo "== Ensure frontend port 443 =="
az network application-gateway frontend-port create -g "$RG" --gateway-name "$APPGW" \
  -n "$FEPORT_443_NAME" --port 443 >/dev/null 2>&1 || true

echo "== Create/Update SSL cert (PFX) =="
# s'il existe, on le supprime puis on recrée (plus robuste que update)
if az network application-gateway ssl-cert show -g "$RG" --gateway-name "$APPGW" -n "$CERT_NAME" >/dev/null 2>&1; then
  az network application-gateway ssl-cert delete -g "$RG" --gateway-name "$APPGW" -n "$CERT_NAME" >/dev/null
fi
az network application-gateway ssl-cert create -g "$RG" --gateway-name "$APPGW" \
  -n "$CERT_NAME" --cert-file "$PFX_PATH" --cert-password "$PFX_PASSWORD" >/dev/null

echo "== Create HTTPS listener =="
FEIP_ID="$(az network application-gateway show -g "$RG" -n "$APPGW" --query "frontendIPConfigurations[0].id" -o tsv)"
FP_ID="$(az network application-gateway frontend-port show -g "$RG" --gateway-name "$APPGW" -n "$FEPORT_443_NAME" --query id -o tsv)"

# si listener existe, delete + recreate
if az network application-gateway http-listener show -g "$RG" --gateway-name "$APPGW" -n "$LISTENER_HTTPS" >/dev/null 2>&1; then
  az network application-gateway http-listener delete -g "$RG" --gateway-name "$APPGW" -n "$LISTENER_HTTPS" >/dev/null
fi

az network application-gateway http-listener create -g "$RG" --gateway-name "$APPGW" \
  -n "$LISTENER_HTTPS" --frontend-ip "$FEIP_ID" --frontend-port "$FP_ID" \
  --protocol Https --ssl-cert "$CERT_NAME" >/dev/null

echo "== Create HTTPS rule (PathBasedRouting) using existing URL path map =="
LISTENER_ID="$(az network application-gateway http-listener show -g "$RG" --gateway-name "$APPGW" -n "$LISTENER_HTTPS" --query id -o tsv)"
UPM_ID="$(az network application-gateway url-path-map show -g "$RG" --gateway-name "$APPGW" -n "$URLPATHMAP" --query id -o tsv)"

# priorité: prendre une valeur libre basse (90) sauf collision
prio=90
used="$(az network application-gateway rule list -g "$RG" --gateway-name "$APPGW" --query "[].priority" -o tsv | tr '\n' ' ')"
while echo " $used " | grep -q " $prio "; do prio=$((prio+1)); done

if az network application-gateway rule show -g "$RG" --gateway-name "$APPGW" -n "$RULE_HTTPS" >/dev/null 2>&1; then
  az network application-gateway rule delete -g "$RG" --gateway-name "$APPGW" -n "$RULE_HTTPS" >/dev/null
fi

az network application-gateway rule create -g "$RG" --gateway-name "$APPGW" \
  -n "$RULE_HTTPS" --rule-type PathBasedRouting --http-listener "$LISTENER_ID" \
  --url-path-map "$UPM_ID" --priority "$prio" >/dev/null

echo "== Create redirect config HTTP->HTTPS =="
if az network application-gateway redirect-config show -g "$RG" --gateway-name "$APPGW" -n "$REDIRECT_NAME" >/dev/null 2>&1; then
  az network application-gateway redirect-config delete -g "$RG" --gateway-name "$APPGW" -n "$REDIRECT_NAME" >/dev/null
fi

az network application-gateway redirect-config create -g "$RG" --gateway-name "$APPGW" \
  -n "$REDIRECT_NAME" --type Permanent --include-path true --include-query-string true \
  --target-listener "$LISTENER_HTTPS" >/dev/null

echo "== Update HTTP rule to redirect =="
az network application-gateway rule update -g "$RG" --gateway-name "$APPGW" \
  -n "$HTTP_RULE" --redirect-config "$REDIRECT_NAME" >/dev/null

echo ""
echo "✅ Done: HTTPS 443 enabled + HTTP redirected."
echo "Rollback (git): git reset --hard HEAD~1"
