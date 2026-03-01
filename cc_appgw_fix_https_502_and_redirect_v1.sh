#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

HTTPS_RULE="rule-https-api-to-backend"
HTTPS_LISTENER="lst-https-api"
BHS="bhs-api-8000"
BPOOL_OK="bp-api-ilb"

HTTP_RULE="rule1"
REDIR_NAME="redir-http-to-https"

echo "== [1] Show current rules (name/priority/listener/pool/httpSettings) =="
az network application-gateway rule list -g "$RG" --gateway-name "$APPGW" \
  --query "[].{name:name,priority:priority,listener: httpListener.id, pool:backendAddressPool.id, bhs:backendHttpSettings.id, redirect:redirectConfiguration.id}" \
  -o jsonc

echo ""
echo "== [2] Ensure HTTPS rule points to healthy backend pool ($BPOOL_OK) + settings ($BHS) =="
CUR_PRIO="$(az network application-gateway rule show -g "$RG" --gateway-name "$APPGW" -n "$HTTPS_RULE" --query "priority" -o tsv 2>/dev/null || true)"
echo "Current priority for $HTTPS_RULE = ${CUR_PRIO:-<none>}"

az network application-gateway rule update \
  -g "$RG" --gateway-name "$APPGW" -n "$HTTPS_RULE" \
  --http-listener "$HTTPS_LISTENER" \
  --address-pool "$BPOOL_OK" \
  --http-settings "$BHS" \
  >/dev/null

# re-set priority if it exists (avoid API complaining later)
if [[ -n "${CUR_PRIO:-}" && "${CUR_PRIO:-}" != "None" ]]; then
  az network application-gateway rule update \
    -g "$RG" --gateway-name "$APPGW" -n "$HTTPS_RULE" \
    --priority "$CUR_PRIO" \
    >/dev/null
  echo "✅ HTTPS rule updated + priority kept: $CUR_PRIO"
else
  echo "✅ HTTPS rule updated (priority unchanged/not set here)"
fi

echo ""
echo "== [3] Ensure redirect config exists ($REDIR_NAME) to HTTPS listener ($HTTPS_LISTENER) =="
if az network application-gateway redirect-config show -g "$RG" --gateway-name "$APPGW" -n "$REDIR_NAME" >/dev/null 2>&1; then
  echo "✅ Redirect-config exists: $REDIR_NAME"
else
  az network application-gateway redirect-config create \
    -g "$RG" --gateway-name "$APPGW" -n "$REDIR_NAME" \
    --type Permanent --target-listener "$HTTPS_LISTENER" \
    >/dev/null
  echo "✅ Created redirect-config: $REDIR_NAME"
fi

echo ""
echo "== [4] Attach redirect to HTTP rule ($HTTP_RULE) =="
az network application-gateway rule update \
  -g "$RG" --gateway-name "$APPGW" -n "$HTTP_RULE" \
  --redirect-config "$REDIR_NAME" \
  >/dev/null
echo "✅ Updated: $HTTP_RULE -> redirect $REDIR_NAME"

echo ""
echo "== [5] Quick backend health after change =="
az network application-gateway show-backend-health -g "$RG" -n "$APPGW" \
  --query "backendAddressPools[].backendHttpSettingsCollection[].servers[].{address:address,health:health,log:healthProbeLog}" \
  -o table

echo ""
echo "== Done =="
echo "Rollback (git): git reset --hard HEAD~1"
