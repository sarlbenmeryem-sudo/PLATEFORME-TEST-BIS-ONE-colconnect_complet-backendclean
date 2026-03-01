#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Add WAF RateLimitRule r3 for /api/ via atomic customRules set
# ID: CC_PATCH_WAF_ADD_R3_RATELIMIT_API_V8_20260301
# ============================

RG="rg-colconnect-prod-frc"
POLICY="wafp-colconnect-prod"

DURATION="OneMin"
THRESHOLD=200
SCOPE_PREFIX="/api/"

echo "== [CC_PATCH_WAF_ADD_R3_RATELIMIT_API_V8] Start =="

az account show -o none
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" -o none

echo "== Fetch existing r1 and r2 objects =="
R1="$(az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query "customRules[?name=='r1'] | [0]" -o json)"
R2="$(az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query "customRules[?name=='r2'] | [0]" -o json)"

if [[ "$R1" == "null" || -z "$R1" ]]; then
  echo "❌ r1 not found. Stop."
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi
if [[ "$R2" == "null" || -z "$R2" ]]; then
  echo "❌ r2 not found. Stop."
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi

echo "✅ r1 and r2 found"

echo ""
echo "== Apply customRules atomically: r1 + r2 + r3 (RateLimitRule) =="

az network application-gateway waf-policy update \
  -g "$RG" -n "$POLICY" \
  --set customRules="[
    $R1,
    $R2,
    {
      \"name\": \"r3\",
      \"priority\": 30,
      \"ruleType\": \"RateLimitRule\",
      \"action\": \"Block\",
      \"rateLimitDuration\": \"$DURATION\",
      \"rateLimitThreshold\": $THRESHOLD,
      \"groupByUserSession\": [
        {
          \"groupByVariables\": [
            { \"variableName\": \"ClientAddr\" }
          ]
        }
      ],
      \"matchConditions\": [
        {
          \"matchVariables\": [
            { \"variableName\": \"RequestUri\" }
          ],
          \"operator\": \"BeginsWith\",
          \"matchValues\": [\"$SCOPE_PREFIX\"],
          \"negationConditon\": false,
          \"transforms\": [\"Lowercase\"]
        }
      ]
    }
  ]" \
  -o none

echo "✅ Added r3 (RateLimitRule)"

echo ""
echo "== Verify custom rules =="
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" \
  --query "customRules[].{name:name,priority:priority,ruleType:ruleType,action:action}" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
