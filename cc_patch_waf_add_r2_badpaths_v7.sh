#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Add WAF custom rule r2 (bad paths) while preserving existing rules
# ID: CC_PATCH_WAF_ADD_R2_BADPATHS_V7_20260301
# ============================

RG="rg-colconnect-prod-frc"
POLICY="wafp-colconnect-prod"

echo "== [CC_PATCH_WAF_ADD_R2_BADPATHS_V7] Start =="

az account show -o none
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" -o none

echo "== Read existing customRules (must include r1) =="
EXISTING="$(az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query "customRules" -o json)"
echo "$EXISTING" | head -c 2000; echo ""

HAS_R1="$(echo "$EXISTING" | grep -c '"name"[[:space:]]*:[[:space:]]*"r1"' || true)"
echo "HAS_R1=$HAS_R1"
if [[ "${HAS_R1:-0}" -lt 1 ]]; then
  echo "❌ r1 not found; refusing to proceed."
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi

echo ""
echo "== Apply customRules atomically: keep r1 and add r2 =="
# We set customRules to: [ <existing r1 object>, <new r2 object> ]
# To avoid JSON surgery issues, we re-fetch r1 object via query.
R1_OBJ="$(az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query "customRules[?name=='r1'] | [0]" -o json)"

az network application-gateway waf-policy update \
  -g "$RG" -n "$POLICY" \
  --set customRules="[
    $R1_OBJ,
    {
      \"name\": \"r2\",
      \"priority\": 20,
      \"ruleType\": \"MatchRule\",
      \"action\": \"Block\",
      \"matchConditions\": [
        {
          \"matchVariables\": [
            {\"variableName\": \"RequestUri\"}
          ],
          \"operator\": \"Contains\",
          \"matchValues\": [
            \"/wp-admin\",\"/wp-login\",\".env\",\"/.git\",\"/phpmyadmin\",\"/cgi-bin\"
          ],
          \"negationConditon\": false,
          \"transforms\": [\"Lowercase\"]
        }
      ]
    }
  ]" \
  -o none

echo "✅ Added r2 while preserving r1"

echo ""
echo "== Verify =="
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" \
  --query "customRules[].{name:name,priority:priority,ruleType:ruleType,action:action,conditions:length(matchConditions)}" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
