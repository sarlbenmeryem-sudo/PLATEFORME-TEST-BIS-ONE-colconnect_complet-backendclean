#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: WAF custom rules production (anti-scan + optional docs allowlist) - v2 JSON file
# ID: CC_PATCH_WAF_CUSTOM_RULES_PROD_V2_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

# Optional: lock /api/docs & /openapi.json to your IPs (empty = disabled)
DOCS_ALLOWLIST_IPS=()   # ex: ("1.2.3.4/32")

need(){ command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing $1" >&2; exit 1; }; }
need az
need jq
need mktemp

az account show -o none

az_retry() {
  local max=12 n=1 delay=7
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
      echo "⏳ Azure transient error (retry $n/$max) in ${delay}s..."
      sleep "$delay"; n=$((n+1)); delay=$((delay+5))
      continue
    fi
    echo "❌ Azure command failed:" >&2
    echo "$out" >&2
    return 1
  done
}

policy_id="$(az network application-gateway show -g "$RG" -n "$APPGW" --query "firewallPolicy.id" -o tsv)"
policy_name="$(echo "$policy_id" | awk -F/ '{print $NF}')"
if [[ -z "${policy_name:-}" ]]; then
  echo "❌ Cannot resolve attached WAF policy name" >&2
  exit 1
fi
echo "== Policy: $policy_name =="

tmpdir="$(mktemp -d)"
cleanup(){ rm -rf "$tmpdir"; }
trap cleanup EXIT

echo ""
echo "== [1] Anti-scan path blocks (cr-block-common-scans) =="

# Match-conditions JSON via file (robust)
mc1="$tmpdir/match_conditions_scans.json"
cat > "$mc1" <<'JSON'
[
  {
    "matchVariables": [
      { "variableName": "RequestUri" }
    ],
    "operator": "Regex",
    "matchValues": [
      "(?i)(/wp-admin|/wp-login\\.php|/\\.env|/\\.git|/phpmyadmin|/pma|/cgi-bin|/vendor/phpunit|/actuator)"
    ],
    "negationConditon": false,
    "transforms": []
  }
]
JSON

az network application-gateway waf-policy custom-rule delete -g "$RG" --policy-name "$policy_name" --name "cr-block-common-scans" >/dev/null 2>&1 || true

az_retry az network application-gateway waf-policy custom-rule create \
  -g "$RG" --policy-name "$policy_name" \
  --name "cr-block-common-scans" \
  --priority 3 \
  --rule-type MatchRule \
  --action Block \
  --match-conditions @"$mc1" \
  -o none

echo "✅ cr-block-common-scans applied"

echo ""
echo "== [2] Optional docs allowlist (cr-docs-allowlist) =="

az network application-gateway waf-policy custom-rule delete -g "$RG" --policy-name "$policy_name" --name "cr-docs-allowlist" >/dev/null 2>&1 || true

if [[ "${#DOCS_ALLOWLIST_IPS[@]}" -gt 0 ]]; then
  # Build IP list JSON
  ip_vals="$(printf '%s\n' "${DOCS_ALLOWLIST_IPS[@]}" | jq -R . | jq -s .)"

  mc2="$tmpdir/match_conditions_docs.json"
  cat > "$mc2" <<JSON
[
  {
    "matchVariables": [
      { "variableName": "RequestUri" }
    ],
    "operator": "Regex",
    "matchValues": [
      "(?i)^/api/docs$",
      "(?i)^/openapi\\.json$"
    ],
    "negationConditon": false,
    "transforms": []
  },
  {
    "matchVariables": [
      { "variableName": "RemoteAddr" }
    ],
    "operator": "IPMatch",
    "matchValues": $ip_vals,
    "negationConditon": true,
    "transforms": []
  }
]
JSON

  az_retry az network application-gateway waf-policy custom-rule create \
    -g "$RG" --policy-name "$policy_name" \
    --name "cr-docs-allowlist" \
    --priority 4 \
    --rule-type MatchRule \
    --action Block \
    --match-conditions @"$mc2" \
    -o none

  echo "✅ cr-docs-allowlist applied (enabled)"
else
  echo "ℹ️ DOCS_ALLOWLIST_IPS empty -> docs allowlist disabled"
fi

echo ""
echo "== [3] Show policy mode/state =="
az network application-gateway waf-policy show -g "$RG" -n "$policy_name" --query "{mode:policySettings.mode,state:policySettings.state}" -o table

echo ""
echo "== Rollback Git (1 step) =="
echo "git reset --hard HEAD~1"

echo "== Done =="
