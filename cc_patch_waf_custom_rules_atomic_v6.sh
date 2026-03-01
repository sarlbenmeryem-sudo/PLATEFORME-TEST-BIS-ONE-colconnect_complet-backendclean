#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Set WAF customRules atomically (bypass match-conditions parser + no-empty-rule constraint)
# ID: CC_PATCH_WAF_CUSTOM_RULES_ATOMIC_V6_20260301
# ============================

RG="rg-colconnect-prod-frc"
POLICY="wafp-colconnect-prod"

echo "== [CC_PATCH_WAF_CUSTOM_RULES_ATOMIC_V6] Start =="

az account show -o none
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" -o none

echo ""
echo "== Safety check: current customRules count (expect 0) =="
CUR_COUNT="$(az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query "length(customRules)" -o tsv)"
echo "customRules count = $CUR_COUNT"
if [[ "${CUR_COUNT:-0}" != "0" ]]; then
  echo "❌ Refusing to overwrite existing customRules (count != 0)."
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi

echo ""
echo "== Apply customRules atomically (1 rule: block UA scanners) =="

# NOTE:
# - name must be alphanum; we use "r1"
# - ruleType MatchRule, action Block
# - matchConditions uses ARM shape (matchVariables/operator/matchValues/transforms)
az network application-gateway waf-policy update \
  -g "$RG" -n "$POLICY" \
  --set customRules="[
    {
      \"name\": \"r1\",
      \"priority\": 10,
      \"ruleType\": \"MatchRule\",
      \"action\": \"Block\",
      \"matchConditions\": [
        {
          \"matchVariables\": [
            {\"variableName\": \"RequestHeaders\", \"selector\": \"User-Agent\"}
          ],
          \"operator\": \"Contains\",
          \"matchValues\": [
            \"sqlmap\",\"nmap\",\"nikto\",\"gobuster\",\"dirbuster\",\"wpscan\",
            \"acunetix\",\"nessus\",\"openvas\",\"zgrab\",\"python-requests\"
          ],
          \"negationConditon\": false,
          \"transforms\": [\"Lowercase\"]
        }
      ]
    }
  ]" \
  -o none

echo "✅ customRules applied (r1)"

echo ""
echo "== Verify =="
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" \
  --query "customRules[].{name:name,priority:priority,ruleType:ruleType,action:action,conditions:length(matchConditions)}" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
