#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: AppGW WAF Detection + WAF Policy + Logs (v2 - fixed CLI)
# ID: CC_PATCH_APPGW_WAF_DETECTION_V2_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

# WAF Policy
WAF_POLICY="wafp-colconnect-prod-frc"
WAF_MODE="Detection"     # Detection first
CRS_TRY=("3.3" "3.2")    # try latest first

# Log Analytics
LAW="law-colconnect-prod-frc"
LAW_SKU="PerGB2018"
DIAG_NAME="diag-${APPGW}-to-${LAW}"

# Custom rules
IP_BLOCKLIST=("203.0.113.10/32" "198.51.100.0/24")  # <-- remplace par ta vraie blocklist
UA_BLOCK_REGEX="(?i)(sqlmap|nikto|acunetix|netsparker|masscan|nmap|zgrab|curl|wget|python-requests|httpclient|go-http-client)"

RATE_LIMIT_THRESHOLD=200
RATE_LIMIT_DURATION=60

echo "== [CC_PATCH_APPGW_WAF_DETECTION_V2_20260301] Start =="

need() { command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing $1" >&2; exit 1; }; }
need az
need jq

az account show -o none

echo "== az version =="
az version | jq -r '.["azure-cli"]' 2>/dev/null || az version || true

# Generic retry for transient Azure errors (including AppGW busy cases)
az_retry() {
  local max=12
  local n=1
  local delay=7
  while true; do
    set +e
    out="$("$@" 2>&1)"
    code=$?
    set -e
    if [[ $code -eq 0 ]]; then
      return 0
    fi
    if echo "$out" | grep -Eqi "PutApplicationGatewayOperation|Another operation is in progress|OperationPreempted|was being modified|TooManyRequests|429|timeout|temporar|Transient"; then
      if [[ $n -ge $max ]]; then
        echo "❌ Retry exhausted ($max). Last error:" >&2
        echo "$out" >&2
        return 1
      fi
      echo "⏳ Azure transient error (retry $n/$max) in ${delay}s..."
      sleep "$delay"
      n=$((n+1))
      delay=$((delay+5))
      continue
    fi
    echo "❌ Azure command failed:" >&2
    echo "$out" >&2
    return 1
  done
}

appgw_id="$(az network application-gateway show -g "$RG" -n "$APPGW" --query id -o tsv)"
if [[ -z "${appgw_id:-}" ]]; then
  echo "❌ AppGW not found: $APPGW in $RG" >&2
  exit 1
fi

echo ""
echo "== [1] Ensure Log Analytics Workspace =="
if az monitor log-analytics workspace show -g "$RG" -n "$LAW" >/dev/null 2>&1; then
  echo "✅ LAW exists: $LAW"
else
  echo "Creating LAW: $LAW"
  az_retry az monitor log-analytics workspace create -g "$RG" -n "$LAW" --sku "$LAW_SKU" -o none
fi
law_id="$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query id -o tsv)"

echo ""
echo "== [2] Ensure WAF Policy exists =="
if az network application-gateway waf-policy show -g "$RG" -n "$WAF_POLICY" >/dev/null 2>&1; then
  echo "✅ WAF Policy exists: $WAF_POLICY"
else
  echo "Creating WAF Policy: $WAF_POLICY"
  az_retry az network application-gateway waf-policy create -g "$RG" -n "$WAF_POLICY" -o none
fi

echo ""
echo "== [3] Configure managed rules (OWASP CRS) + mode =="
crs_ok="no"
for crs in "${CRS_TRY[@]}"; do
  echo "-- Trying CRS $crs --"
  set +e
  # ✅ FIX: correct subcommand is 'managed-rule rule-set add' (NOT 'set add')
  out="$(az network application-gateway waf-policy managed-rule rule-set add \
    -g "$RG" --policy-name "$WAF_POLICY" \
    --type OWASP --version "$crs" -o none 2>&1)"
  code=$?
  set -e
  if [[ $code -eq 0 ]]; then
    crs_ok="yes"
    echo "✅ CRS enabled: OWASP $crs"
    break
  else
    echo "⚠️ CRS $crs not applied. First lines:"
    echo "$out" | sed -n '1,10p'
  fi
done
if [[ "$crs_ok" != "yes" ]]; then
  echo "❌ Could not enable OWASP CRS (tried: ${CRS_TRY[*]})." >&2
  echo "   Debug hint: run -> az network application-gateway waf-policy managed-rule -h" >&2
  exit 1
fi

az_retry az network application-gateway waf-policy policy-setting update \
  -g "$RG" --policy-name "$WAF_POLICY" \
  --mode "$WAF_MODE" \
  --state Enabled \
  --request-body-check true \
  --max-request-body-size-in-kb 128 \
  --file-upload-limit-in-mb 100 \
  -o none
echo "✅ WAF policy settings updated (mode=$WAF_MODE)"

echo ""
echo "== [4] Custom rules (IP blocklist + UA bots) =="

# IP blocklist
if [[ "${#IP_BLOCKLIST[@]}" -gt 0 ]]; then
  ip_vals="$(printf '%s\n' "${IP_BLOCKLIST[@]}" | jq -R . | jq -s .)"

  az network application-gateway waf-policy custom-rule delete \
    -g "$RG" --policy-name "$WAF_POLICY" --name "cr-ip-blocklist" >/dev/null 2>&1 || true

  az_retry az network application-gateway waf-policy custom-rule create \
    -g "$RG" --policy-name "$WAF_POLICY" \
    --name "cr-ip-blocklist" \
    --priority 5 \
    --rule-type MatchRule \
    --action Block \
    --match-conditions "[{
      \"matchVariables\": [{\"variableName\":\"RemoteAddr\"}],
      \"operator\": \"IPMatch\",
      \"matchValues\": ${ip_vals},
      \"negationConditon\": false,
      \"transforms\": []
    }]" \
    -o none
  echo "✅ Custom rule: IP blocklist"
else
  echo "ℹ️ IP_BLOCKLIST empty -> skip"
fi

# UA bots/scanners
az network application-gateway waf-policy custom-rule delete \
  -g "$RG" --policy-name "$WAF_POLICY" --name "cr-ua-bots" >/dev/null 2>&1 || true

az_retry az network application-gateway waf-policy custom-rule create \
  -g "$RG" --policy-name "$WAF_POLICY" \
  --name "cr-ua-bots" \
  --priority 10 \
  --rule-type MatchRule \
  --action Block \
  --match-conditions "[{
    \"matchVariables\": [{\"variableName\":\"RequestHeaders\",\"selector\":\"User-Agent\"}],
    \"operator\": \"Regex\",
    \"matchValues\": [\"$UA_BLOCK_REGEX\"],
    \"negationConditon\": false,
    \"transforms\": []
  }]" \
  -o none
echo "✅ Custom rule: UA bots/scanners"

echo ""
echo "== [5] Rate limiting (best effort) =="
az network application-gateway waf-policy custom-rule delete \
  -g "$RG" --policy-name "$WAF_POLICY" --name "cr-rate-limit" >/dev/null 2>&1 || true

set +e
rl_out="$(az network application-gateway waf-policy custom-rule create \
  -g "$RG" --policy-name "$WAF_POLICY" \
  --name "cr-rate-limit" \
  --priority 20 \
  --rule-type RateLimitRule \
  --action Block \
  --rate-limit-duration "$RATE_LIMIT_DURATION" \
  --rate-limit-threshold "$RATE_LIMIT_THRESHOLD" \
  --match-conditions "[{
    \"matchVariables\": [{\"variableName\":\"RemoteAddr\"}],
    \"operator\": \"IPMatch\",
    \"matchValues\": [\"0.0.0.0/0\"],
    \"negationConditon\": false,
    \"transforms\": []
  }]" 2>&1)"
rl_code=$?
set -e
if [[ $rl_code -eq 0 ]]; then
  echo "✅ Rate limiting enabled: ${RATE_LIMIT_THRESHOLD}/${RATE_LIMIT_DURATION}s"
else
  echo "⚠️ Rate limiting not applied (unsupported). Keeping WAF without RL."
  echo "$rl_out" | sed -n '1,10p'
fi

echo ""
echo "== [6] Associate WAF policy to AppGW (PutApplicationGatewayOperation retry-ready) =="
waf_id="$(az network application-gateway waf-policy show -g "$RG" -n "$WAF_POLICY" --query id -o tsv)"
az_retry az network application-gateway update \
  -g "$RG" -n "$APPGW" \
  --set firewallPolicy.id="$waf_id" \
  -o none
echo "✅ WAF policy associated to AppGW"

echo ""
echo "== [7] Diagnostic settings to Log Analytics (Access/Perf/WAF) =="
# Create or update diag
az monitor diagnostic-settings create \
  --name "$DIAG_NAME" \
  --resource "$appgw_id" \
  --workspace "$law_id" \
  --logs '[
    {"category":"ApplicationGatewayAccessLog","enabled":true},
    {"category":"ApplicationGatewayPerformanceLog","enabled":true},
    {"category":"ApplicationGatewayFirewallLog","enabled":true}
  ]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]' \
  -o none >/dev/null 2>&1 || \
az monitor diagnostic-settings update \
  --name "$DIAG_NAME" \
  --resource "$appgw_id" \
  --workspace "$law_id" \
  -o none
echo "✅ Diagnostics configured"

echo ""
echo "== [8] Checks =="
az network application-gateway show-backend-health -g "$RG" -n "$APPGW" -o table || true
az network application-gateway waf-policy show -g "$RG" -n "$WAF_POLICY" --query "policySettings.mode" -o tsv | awk '{print "WAF mode: "$1}'

echo ""
echo "== Rollback Git (1 step) =="
echo "git reset --hard HEAD~1"

echo ""
echo "== [CC_PATCH_APPGW_WAF_DETECTION_V2_20260301] Done =="
