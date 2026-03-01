#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Add WAF RateLimitRule r3 for /api/ (AAZ shorthand for group-by + match-conditions)
# ID: CC_PATCH_WAF_ADD_R3_RATELIMIT_API_V6_20260301
# ============================

RG="rg-colconnect-prod-frc"
POLICY="wafp-colconnect-prod"

RULE="r3"
PRIORITY="30"
DURATION="OneMin"
THRESHOLD="200"
SCOPE_PREFIX="/api/"

echo "== [CC_PATCH_WAF_ADD_R3_RATELIMIT_API_V6] Start =="

az account show -o none
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" -o none

echo "== Recreate rule: $RULE (RateLimitRule) =="

if az network application-gateway waf-policy custom-rule show -g "$RG" --policy-name "$POLICY" -n "$RULE" >/dev/null 2>&1; then
  az network application-gateway waf-policy custom-rule delete -g "$RG" --policy-name "$POLICY" -n "$RULE" -o none
  echo "ℹ️ Deleted existing rule: $RULE"
fi

echo "== Create RateLimitRule r3 =="

az network application-gateway waf-policy custom-rule create \
  -g "$RG" --policy-name "$POLICY" -n "$RULE" \
  --priority "$PRIORITY" \
  --rule-type RateLimitRule \
  --action Block \
  --rate-limit-duration "$DURATION" \
  --rate-limit-threshold "$THRESHOLD" \
  --group-by-user-session "[{group-by-variables:[{variable-name:ClientAddr}]}]" \
  --match-conditions "[{match-variables:[{variable-name:RequestUri}],operator:BeginsWith,match-values:[$SCOPE_PREFIX],negation-condition:false,transforms:[Lowercase]}]" \
  -o none

echo "✅ Created RateLimitRule: $RULE"

echo ""
echo "== Verify custom rules =="
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" \
  --query "customRules[].{name:name,priority:priority,ruleType:ruleType,action:action}" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
