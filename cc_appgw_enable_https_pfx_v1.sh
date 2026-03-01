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

CERT_NAME="cc-cert-pfx"
HTTPS_PORT_NAME="feport-443"
HTTPS_PORT="443"
HTTPS_LISTENER="listener-https-443"
RULE_HTTPS="rule-https"
URLPATHMAP="upm-colconnect"

echo "== Ensure frontend port 443 =="
az network application-gateway frontend-port create -g "$RG" --gateway-name "$APPGW" \
  -n "$HTTPS_PORT_NAME" --port "$HTTPS_PORT" >/dev/null || true

echo "== Upload SSL cert (PFX) =="
az network application-gateway ssl-cert create -g "$RG" --gateway-name "$APPGW" \
  -n "$CERT_NAME" --cert-file "$PFX_PATH" --cert-password "$PFX_PASSWORD" >/dev/null || true

echo "== Create HTTPS listener (443) =="
FEIP_ID="$(az network application-gateway show -g "$RG" -n "$APPGW" --query "frontendIPConfigurations[0].id" -o tsv)"
FP_ID="$(az network application-gateway frontend-port show -g "$RG" --gateway-name "$APPGW" -n "$HTTPS_PORT_NAME" --query id -o tsv)"
az network application-gateway http-listener create -g "$RG" --gateway-name "$APPGW" \
  -n "$HTTPS_LISTENER" --frontend-ip "$FEIP_ID" --frontend-port "$FP_ID" \
  --protocol Https --ssl-cert "$CERT_NAME" >/dev/null || true

echo "== Create HTTPS routing rule using existing URL path map =="
LISTENER_ID="$(az network application-gateway http-listener show -g "$RG" --gateway-name "$APPGW" -n "$HTTPS_LISTENER" --query id -o tsv)"
UPM_ID="$(az network application-gateway url-path-map show -g "$RG" --gateway-name "$APPGW" -n "$URLPATHMAP" --query id -o tsv)"
az network application-gateway rule create -g "$RG" --gateway-name "$APPGW" \
  -n "$RULE_HTTPS" --rule-type PathBasedRouting --http-listener "$LISTENER_ID" \
  --url-path-map "$UPM_ID" --priority 90 >/dev/null || true

echo "✅ HTTPS listener+rule created. (Next: HTTP->HTTPS redirect)"
echo "Rollback (git): git reset --hard HEAD~1"
