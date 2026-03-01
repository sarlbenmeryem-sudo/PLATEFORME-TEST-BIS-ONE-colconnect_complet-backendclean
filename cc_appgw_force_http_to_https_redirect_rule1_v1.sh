#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

HTTP_RULE="rule1"
HTTP_LISTENER="appGatewayHttpListener"     # listener 80 existant
REDIR_NAME="redir-http-to-https"
HTTPS_LISTENER="lst-https-api"             # listener 443

PRIORITY="${HTTP_RULE_PRIORITY:-100}"

retry_put() {
  local n=0
  local max=8
  local wait=15
  while true; do
    n=$((n+1))
    if "$@"; then
      return 0
    fi
    if [[ $n -ge $max ]]; then
      echo "❌ Failed after $n attempts: $*" >&2
      return 1
    fi
    echo "⚠️ Put canceled/superseded. Retry $n/$max in ${wait}s..."
    sleep "$wait"
  done
}

echo "== [0] Show current rule1 =="
az network application-gateway rule show -g "$RG" --gateway-name "$APPGW" -n "$HTTP_RULE" -o jsonc || true

echo ""
echo "== [1] Ensure redirect-config exists: $REDIR_NAME -> $HTTPS_LISTENER =="
if az network application-gateway redirect-config show -g "$RG" --gateway-name "$APPGW" -n "$REDIR_NAME" >/dev/null 2>&1; then
  echo "✅ Redirect-config exists"
else
  retry_put az network application-gateway redirect-config create \
    -g "$RG" --gateway-name "$APPGW" -n "$REDIR_NAME" \
    --type Permanent \
    --target-listener "$HTTPS_LISTENER" \
    --include-path true \
    --include-query-string true \
    >/dev/null
  echo "✅ Created redirect-config"
fi

echo ""
echo "== [2] Delete rule1 (to remove any leftover backend binding) =="
if az network application-gateway rule show -g "$RG" --gateway-name "$APPGW" -n "$HTTP_RULE" >/dev/null 2>&1; then
  retry_put az network application-gateway rule delete -g "$RG" --gateway-name "$APPGW" -n "$HTTP_RULE" >/dev/null
  echo "✅ Deleted $HTTP_RULE"
else
  echo "ℹ️ $HTTP_RULE not found (ok)"
fi

echo ""
echo "== [3] Recreate rule1 as redirect-only (priority=$PRIORITY) =="
retry_put az network application-gateway rule create \
  -g "$RG" --gateway-name "$APPGW" -n "$HTTP_RULE" \
  --http-listener "$HTTP_LISTENER" \
  --rule-type Basic \
  --priority "$PRIORITY" \
  --redirect-config "$REDIR_NAME" \
  >/dev/null
echo "✅ Recreated $HTTP_RULE as redirect-only"

echo ""
echo "== [4] Verify rule1 now =="
az network application-gateway rule show -g "$RG" --gateway-name "$APPGW" -n "$HTTP_RULE" \
  --query "{name:name,priority:priority,listener:httpListener.id,redirect:redirectConfiguration.id,backendPool:backendAddressPool,backendHttpSettings:backendHttpSettings}" -o jsonc

echo ""
echo "== Done =="
echo "Rollback (git): git reset --hard HEAD~1"
