#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

HTTP_RULE="rule1"                 # ta rule actuelle sur HTTP
HTTPS_LISTENER="listener-https-443"
REDIRECT_NAME="redir-http-to-https"

echo "== Create redirect config =="
az network application-gateway redirect-config create -g "$RG" --gateway-name "$APPGW" \
  -n "$REDIRECT_NAME" --type Permanent --include-path true --include-query-string true \
  --target-listener "$HTTPS_LISTENER" >/dev/null || true

echo "== Update HTTP rule to redirect =="
az network application-gateway rule update -g "$RG" --gateway-name "$APPGW" \
  -n "$HTTP_RULE" --redirect-config "$REDIRECT_NAME" >/dev/null

echo "✅ HTTP redirected to HTTPS."
echo "Rollback (git): git reset --hard HEAD~1"
