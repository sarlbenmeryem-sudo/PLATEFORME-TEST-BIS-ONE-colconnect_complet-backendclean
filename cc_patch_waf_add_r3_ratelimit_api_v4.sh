#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Add WAF RateLimitRule r3 for /api/ (auto-detect group-by schema)
# ID: CC_PATCH_WAF_ADD_R3_RATELIMIT_API_V4_20260301
# ============================

RG="rg-colconnect-prod-frc"
POLICY="wafp-colconnect-prod"

RULE="r3"
PRIORITY="30"
DURATION="OneMin"
THRESHOLD="200"
SCOPE_PREFIX="/api/"

echo "== [CC_PATCH_WAF_ADD_R3_RATELIMIT_API_V4] Start =="

az account show -o none
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" -o none

echo "== Detect group-by schema from CLI help =="
HELP="$(az network application-gateway waf-policy custom-rule create -h 2>/dev/null || true)"

GB_JSON=''

# Try infer expected dict keys
# We look for patterns like "name=" or "groupByVariable=" etc. in the help block
if echo "$HELP" | grep -q -- "--group-by-user-session"; then
  # Most AAZ models expose "name" for enum-like dict entries
  if echo "$HELP" | sed -n '/--group-by-user-session/,/--/p' | grep -qi "name"; then
    GB_JSON='[{"name":"ClientAddr"}]'
  elif echo "$HELP" | sed -n '/--group-by-user-session/,/--/p' | grep -qi "groupByVariable"; then
    GB_JSON='[{"groupByVariable":"ClientAddr"}]'
  elif echo "$HELP" | sed -n '/--group-by-user-session/,/--/p' | grep -qi "variable"; then
    GB_JSON='[{"variable":"ClientAddr"}]'
  else
    # Fallback: most common in these CLIs is "name"
    GB_JSON='[{"name":"ClientAddr"}]'
  fi
else
  echo "❌ Cannot find --group-by-user-session in help. Stop."
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi

echo "Using group-by json: $GB_JSON"

echo ""
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
  --group-by-user-session "$GB_JSON" \
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
