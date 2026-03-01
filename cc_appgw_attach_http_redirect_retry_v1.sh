#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

HTTP_RULE="rule1"
REDIR_NAME="redir-http-to-https"
HTTPS_LISTENER="lst-https-api"

echo "== [0] Ensure redirect-config exists =="
if az network application-gateway redirect-config show -g "$RG" --gateway-name "$APPGW" -n "$REDIR_NAME" >/dev/null 2>&1; then
  echo "✅ Redirect-config exists: $REDIR_NAME"
else
  az network application-gateway redirect-config create \
    -g "$RG" --gateway-name "$APPGW" -n "$REDIR_NAME" \
    --type Permanent --target-listener "$HTTPS_LISTENER" >/dev/null
  echo "✅ Created redirect-config: $REDIR_NAME"
fi

echo ""
echo "== [1] Attach redirect to HTTP rule with retry/wait =="

attempt=1
max_attempts=6

while (( attempt <= max_attempts )); do
  echo "-- Attempt $attempt/$max_attempts: rule update (attach redirect) --"
  set +e
  OUT="$(az network application-gateway rule update \
    -g "$RG" --gateway-name "$APPGW" -n "$HTTP_RULE" \
    --redirect-config "$REDIR_NAME" 2>&1)"
  RC=$?
  set -e

  if [[ $RC -eq 0 ]]; then
    echo "✅ Redirect attached to $HTTP_RULE"
    break
  fi

  echo "⚠️ Update failed (rc=$RC). Output:"
  echo "$OUT" | sed -n '1,120p'

  echo ""
  echo "== Wait for AppGW to be ready (provisioningState Succeeded) then retry =="
  az network application-gateway wait -g "$RG" -n "$APPGW" --custom "provisioningState=='Succeeded'" >/dev/null || true
  sleep 10

  attempt=$((attempt+1))
done

if (( attempt > max_attempts )); then
  echo "❌ Could not attach redirect after $max_attempts attempts."
  exit 1
fi

echo ""
echo "== [2] Verify rule1 now has redirectConfiguration =="
az network application-gateway rule show -g "$RG" --gateway-name "$APPGW" -n "$HTTP_RULE" \
  --query "{name:name,priority:priority,listener:httpListener.id,redirect:redirectConfiguration.id}" -o jsonc

echo ""
echo "== Done =="
echo "Rollback (git): git reset --hard HEAD~1"
