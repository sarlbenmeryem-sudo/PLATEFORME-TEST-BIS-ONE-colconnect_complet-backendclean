#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Add WAF RateLimitRule r3 for /api/ (AAZ schema group-by-variables)
# ID: CC_PATCH_WAF_ADD_R3_RATELIMIT_API_V5_20260301
# ============================

RG="rg-colconnect-prod-frc"
POLICY="wafp-colconnect-prod"

RULE="r3"
PRIORITY="30"
DURATION="OneMin"
THRESHOLD="200"
SCOPE_PREFIX="/api/"

echo "== [CC_PATCH_WAF_ADD_R3_RATELIMIT_API_V5] Start =="

az account show -o none
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" -o none

echo "== Recreate rule: $RULE (RateLimitRule) =="

if az network application-gateway waf-policy custom-rule show -g "$RG" --policy-name "$POLICY" -n "$RULE" >/dev/null 2>&1; then
  az network application-gateway waf-policy custom-rule delete -g "$RG" --policy-name "$POLICY" -n "$RULE" -o none
  echo "ℹ️ Deleted existing rule: $RULE"
fi

try_create () {
  local VAR="$1"
  echo "== Try group-by variable-name: $VAR =="

  set +e
  OUT="$(az network application-gateway waf-policy custom-rule create \
    -g "$RG" --policy-name "$POLICY" -n "$RULE" \
    --priority "$PRIORITY" \
    --rule-type RateLimitRule \
    --action Block \
    --rate-limit-duration "$DURATION" \
    --rate-limit-threshold "$THRESHOLD" \
    --group-by-user-session "[{group-by-variables:[{variable-name:$VAR}]}]" \
    --match-conditions "matchVariables=[{variableName=RequestUri}],operator=BeginsWith,matchValues=[$SCOPE_PREFIX],negationConditon=false,transforms=[Lowercase]" \
    -o none 2>&1)"
  RC=$?
  set -e

  if [[ $RC -eq 0 ]]; then
    echo "✅ Created r3 with group-by variable-name=$VAR"
    return 0
  fi

  echo "❌ Failed with $VAR:"
  echo "$OUT"
  return 1
}

# Fallback order
try_create "ClientAddr" || try_create "RemoteAddr" || try_create "ClientIP" || {
  echo "❌ Could not create r3 with any known client IP group-by variable."
  echo "Next step: list allowed variable-name values for group-by-variables (we'll extract from help/??)."
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
}

echo ""
echo "== Verify custom rules =="
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" \
  --query "customRules[].{name:name,priority:priority,ruleType:ruleType,action:action}" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
