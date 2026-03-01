#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

# A REMPLACER
KV_NAME="kv-colconnect-prod-frc"
KV_SECRET_NAME="colconnect-tls-pfx"  # secret contenant le PFX (base64) + password géré par KV
CERT_NAME="cc-cert-kv"

HTTPS_PORT_NAME="feport-443"
HTTPS_PORT="443"
HTTPS_LISTENER="listener-https-443"
HTTP_LISTENER="appGatewayHttpListener"
REDIRECT_NAME="redir-http-to-https"
RULE_HTTP="rule1" # ta rule actuelle sur HTTP

echo "== Create/ensure frontend port 443 =="
az network application-gateway frontend-port create -g "$RG" --gateway-name "$APPGW" \
  -n "$HTTPS_PORT_NAME" --port "$HTTPS_PORT" >/dev/null || true

echo "== Attach SSL cert from Key Vault =="
az network application-gateway ssl-cert create -g "$RG" --gateway-name "$APPGW" \
  -n "$CERT_NAME" --key-vault-secret-id "$(az keyvault secret show --vault-name "$KV_NAME" -n "$KV_SECRET_NAME" --query id -o tsv)" >/dev/null || true

echo "== Create HTTPS listener (443) =="
FEIP_ID="$(az network application-gateway show -g "$RG" -n "$APPGW" --query "frontendIPConfigurations[0].id" -o tsv)"
FP_ID="$(az network application-gateway frontend-port show -g "$RG" --gateway-name "$APPGW" -n "$HTTPS_PORT_NAME" --query id -o tsv)"
az network application-gateway http-listener create -g "$RG" --gateway-name "$APPGW" \
  -n "$HTTPS_LISTENER" --frontend-ip "$FEIP_ID" --frontend-port "$FP_ID" \
  --protocol Https --ssl-cert "$CERT_NAME" >/dev/null || true

echo "== Create redirect config (HTTP->HTTPS) =="
az network application-gateway redirect-config create -g "$RG" --gateway-name "$APPGW" \
  -n "$REDIRECT_NAME" --type Permanent --include-path true --include-query-string true \
  --target-listener "$HTTPS_LISTENER" >/dev/null || true

echo "== Update HTTP rule to redirect (instead of backend) =="
az network application-gateway rule update -g "$RG" --gateway-name "$APPGW" \
  -n "$RULE_HTTP" --redirect-config "$REDIRECT_NAME" >/dev/null

echo "✅ HTTPS enabled + HTTP redirected to HTTPS."
echo "Rollback (git): git reset --hard HEAD~1"
