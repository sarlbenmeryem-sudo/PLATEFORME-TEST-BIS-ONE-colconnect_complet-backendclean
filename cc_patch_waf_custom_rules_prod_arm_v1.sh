#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: WAF custom rules via ARM (az rest) to bypass CLI AAZ schema
# ID: CC_PATCH_WAF_CUSTOM_RULES_PROD_ARM_V1_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

# Rule payloads
RULE1_NAME="cr-block-common-scans"
RULE1_PRIORITY=3

RULE1_REGEX="(?i)(/wp-admin|/wp-login\\.php|/\\.env|/\\.git|/phpmyadmin|/pma|/cgi-bin|/vendor/phpunit|/actuator)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing $1" >&2; exit 1; }; }
need az
need jq
need mktemp

az account show -o none

# Find attached WAF policy
policy_id="$(az network application-gateway show -g "$RG" -n "$APPGW" --query "firewallPolicy.id" -o tsv)"
policy_name="$(echo "$policy_id" | awk -F/ '{print $NF}')"
if [[ -z "${policy_name:-}" ]]; then
  echo "❌ Cannot resolve attached WAF policy name" >&2
  exit 1
fi
echo "== Policy: $policy_name =="

sub_id="$(az account show --query id -o tsv)"
url_base="https://management.azure.com/subscriptions/${sub_id}/resourceGroups/${RG}/providers/Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies/${policy_name}"

# Try API versions (newest->older)
api_versions=("2023-09-01" "2022-09-01" "2021-08-01" "2020-11-01")

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo ""
echo "== [1] GET current policy (try api versions) =="

policy_json=""
used_api=""
for v in "${api_versions[@]}"; do
  set +e
  out="$(az rest --method get --url "${url_base}?api-version=${v}" 2>/dev/null)"
  code=$?
  set -e
  if [[ $code -eq 0 && -n "${out:-}" ]]; then
    policy_json="$out"
    used_api="$v"
    break
  fi
done

if [[ -z "${policy_json:-}" ]]; then
  echo "❌ Could not GET policy via az rest (RBAC/API version). Stop." >&2
  exit 1
fi

echo "✅ GET ok (api-version=$used_api)"

# Build rule JSON
rule1="$(jq -n --arg name "$RULE1_NAME" --argjson prio "$RULE1_PRIORITY" --arg rx "$RULE1_REGEX" '
{
  "name": $name,
  "priority": $prio,
  "ruleType": "MatchRule",
  "action": "Block",
  "matchConditions": [
    {
      "matchVariables": [{"variableName":"RequestUri"}],
      "operator": "Regex",
      "matchValues": [$rx],
      "negationConditon": false,
      "transforms": []
    }
  ]
}
')"

echo ""
echo "== [2] Upsert customRules in policy JSON =="

# Ensure properties/customRules exists; remove existing same-name rule; append new
patched="$(echo "$policy_json" | jq --arg rn "$RULE1_NAME" --argjson r "$rule1" '
  .properties.customRules = (.properties.customRules // [])
  | .properties.customRules = ([.properties.customRules[] | select(.name != $rn)] + [$r])
')"

file="$tmpdir/policy_patched.json"
echo "$patched" > "$file"

echo "== [3] PUT updated policy =="

# PUT back
az rest --method put --url "${url_base}?api-version=${used_api}" \
  --headers "Content-Type=application/json" \
  --body @"$file" >/dev/null

echo "✅ PUT ok"

echo ""
echo "== [4] Verify custom rules list (via az CLI) =="
# Even if CLI schema differs for create, list usually works.
az network application-gateway waf-policy custom-rule list -g "$RG" --policy-name "$policy_name" -o table || true

echo ""
echo "== Rollback Git (1 step) =="
echo "git reset --hard HEAD~1"

echo "== Done =="
