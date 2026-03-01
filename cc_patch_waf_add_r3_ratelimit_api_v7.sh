#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Add WAF RateLimitRule r3 for /api/ (JSON file method - AAZ safe)
# ID: CC_PATCH_WAF_ADD_R3_RATELIMIT_API_V7_20260301
# ============================

RG="rg-colconnect-prod-frc"
POLICY="wafp-colconnect-prod"

RULE="r3"
PRIORITY=30
DURATION="OneMin"
THRESHOLD=200
SCOPE_PREFIX="/api/"

echo "== [CC_PATCH_WAF_ADD_R3_RATELIMIT_API_V7] Start =="

az account show -o none
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" -o none

if az network application-gateway waf-policy custom-rule show -g "$RG" --policy-name "$POLICY" -n "$RULE" >/dev/null 2>&1; then
  az network application-gateway waf-policy custom-rule delete -g "$RG" --policy-name "$POLICY" -n "$RULE" -o none
  echo "ℹ️ Deleted existing rule: $RULE"
fi

echo "== Create JSON payload =="

cat > r3_ratelimit.json <<EOF
{
  "priority": $PRIORITY,
  "ruleType": "RateLimitRule",
  "action": "Block",
  "rateLimitDuration": "$DURATION",
  "rateLimitThreshold": $THRESHOLD,
  "groupByUserSession": [
    {
      "groupByVariables": [
        {
          "variableName": "ClientAddr"
        }
      ]
    }
  ],
  "matchConditions": [
    {
      "matchVariables": [
        {
          "variableName": "RequestUri"
        }
      ],
      "operator": "BeginsWith",
      "matchValues": ["$SCOPE_PREFIX"],
      "negationCondition": false,
      "transforms": ["Lowercase"]
    }
  ]
}
EOF

echo "== Create RateLimitRule from JSON =="

az network application-gateway waf-policy custom-rule create \
  -g "$RG" --policy-name "$POLICY" -n "$RULE" \
  --custom-rule-config "@r3_ratelimit.json" \
  -o none

echo "✅ Created RateLimitRule: $RULE"

echo ""
echo "== Verify custom rules =="
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" \
  --query "customRules[].{name:name,priority:priority,ruleType:ruleType,action:action}" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
