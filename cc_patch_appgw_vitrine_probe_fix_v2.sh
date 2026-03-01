#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Fix AppGW probe for Storage Static Website (HTTPS host handling)
# ID: CC_PATCH_APPGW_VITRINE_PROBE_FIX_V2_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

BP="bp-web-static"
BHS="bhs-web-static-https"
PROBE="probe-web-root"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing $1" >&2; exit 1; }; }
need az
need jq

az account show -o none

az_retry() {
  local max=14 n=1 delay=8
  while true; do
    set +e
    out="$("$@" 2>&1)"; code=$?
    set -e
    if [[ $code -eq 0 ]]; then return 0; fi
    if echo "$out" | grep -Eqi "PutApplicationGatewayOperation|Another operation is in progress|OperationPreempted|was being modified|TooManyRequests|429|timeout|temporar|Transient"; then
      if [[ $n -ge $max ]]; then
        echo "❌ Retry exhausted ($max). Last error:" >&2
        echo "$out" >&2
        return 1
      fi
      echo "⏳ AppGW busy/transient (retry $n/$max) in ${delay}s..."
      sleep "$delay"; n=$((n+1)); delay=$((delay+6))
      continue
    fi
    echo "❌ Azure command failed:" >&2
    echo "$out" >&2
    return 1
  done
}

echo "== [1] Detect Storage web host from existing backend pool (preferred) =="

host="$(az network application-gateway address-pool show -g "$RG" --gateway-name "$APPGW" -n "$BP" --query "backendAddresses[0].fqdn" -o tsv 2>/dev/null || true)"
if [[ -z "${host:-}" || "$host" == "null" ]]; then
  echo "Backend pool $BP not found or empty. Trying RG scan..."
  sa_json="$(az storage account list -g "$RG" -o json)"
  web_host="$(echo "$sa_json" | jq -r '
    map({name:.name, web:(.primaryEndpoints.web // "")})
    | map(select(.web != ""))
    | (sort_by(.name) | last | .web) // empty
  ')"
  if [[ -z "${web_host:-}" || "$web_host" == "null" ]]; then
    echo "❌ Cannot find storage web endpoint in RG." >&2
    exit 1
  fi
  host="$(echo "$web_host" | sed -E 's#^https?://##; s#/$##')"
fi
echo "✅ Storage host: $host"

echo ""
echo "== [2] Ensure probe with host-name-from-http-settings =="
if az network application-gateway probe show -g "$RG" --gateway-name "$APPGW" -n "$PROBE" >/dev/null 2>&1; then
  az_retry az network application-gateway probe update -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
    --protocol Https --path "/" --interval 30 --timeout 10 --threshold 3 \
    --host-name-from-http-settings true \
    -o none
  echo "✅ Probe updated: $PROBE"
else
  az_retry az network application-gateway probe create -g "$RG" --gateway-name "$APPGW" -n "$PROBE" \
    --protocol Https --path "/" --interval 30 --timeout 10 --threshold 3 \
    --host-name-from-http-settings true \
    -o none
  echo "✅ Probe created: $PROBE"
fi

echo ""
echo "== [3] Ensure HTTP settings (HTTPS 443) with host-name-from-backend-pool =="
if az network application-gateway http-settings show -g "$RG" --gateway-name "$APPGW" -n "$BHS" >/dev/null 2>&1; then
  az_retry az network application-gateway http-settings update -g "$RG" --gateway-name "$APPGW" -n "$BHS" \
    --port 443 --protocol Https --timeout 30 --probe "$PROBE" \
    --host-name-from-backend-pool true \
    -o none
  echo "✅ HTTP settings updated: $BHS"
else
  az_retry az network application-gateway http-settings create -g "$RG" --gateway-name "$APPGW" -n "$BHS" \
    --port 443 --protocol Https --timeout 30 --probe "$PROBE" \
    --host-name-from-backend-pool true \
    --probe "$PROBE" \
    -o none
  echo "✅ HTTP settings created: $BHS"
fi

echo ""
echo "== [4] Quick backend health view (may still depend on rule/listener) =="
az network application-gateway show-backend-health -g "$RG" -n "$APPGW" -o table || true

echo ""
echo "== Rollback Git (1 step) =="
echo "git reset --hard HEAD~1"
echo "== Done =="
