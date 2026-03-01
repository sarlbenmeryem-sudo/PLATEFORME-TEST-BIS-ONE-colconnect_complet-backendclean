#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Add WAF RateLimitRule r3 for /api/ (group-by dict list)
# ID: CC_PATCH_WAF_ADD_R3_RATELIMIT_API_V3_20260301
# ============================

RG="rg-colconnect-prod-frc"
POLICY="wafp-colconnect-prod"

RULE="r3"
PRIORITY="30"
DURATION="OneMin"
THRESHOLD="200"
SCOPE_PREFIX="/api/"

echo "== [CC_PATCH_WAF_ADD_R3_RATELIMIT_API_V3] Start =="

az account show -o none
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" -o none

echo "== Recreate rule: $RULE (RateLimitRule) =="

if az network application-gateway waf-policy custom-rule show -g "$RG" --policy-name "$POLICY" -n "$RULE" >/dev/null 2>&1; then
  az network application-gateway waf-policy custom-rule delete -g "$RG" --policy-name "$POLICY" -n "$RULE" -o none
  echo "ℹ️ Deleted existing rule: $RULE"
fi

az network application-gateway waf-policy custom-rule create \
  -g "$RG" --policy-name "$POLICY" -n "$RULE" \
  --priority "$PRIORITY" \
  --rule-type RateLimitRule \
  --action Block \
  --rate-limit-duration "$DURATION" \
  --rate-limit-threshold "$THRESHOLD" \
  --group-by-user-session '[{"variableName":"ClientAddr"}]' \
  --match-conditions "matchVariables=[{variableName=RequestUri}],operator=BeginsWith,matchValues=[$SCOPE_PREFIX],negationConditon=false,transforms=[Lowercase]" \
  -o none

echo "✅ Created RateLimitRule: $RULE"

echo ""
echo "== Verify custom rules =="
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" \
  --query "customRules[].{name:name,priority:priority,ruleType:ruleType,action:action}" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
