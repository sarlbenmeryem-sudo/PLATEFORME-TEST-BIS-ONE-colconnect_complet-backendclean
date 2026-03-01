#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: r6 block empty User-Agent on docs/openapi endpoints
# ID: CC_PATCH_WAF_ADD_R6_BLOCK_EMPTY_UA_DOCS_V1_20260301
# ============================

RG="rg-colconnect-prod-frc"
POLICY="wafp-colconnect-prod"

echo "== [CC_PATCH_WAF_ADD_R6_BLOCK_EMPTY_UA_DOCS_V1] Start =="

az account show -o none
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" -o none

# Fetch current rules r1..r5
RULES_JSON="$(az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query "customRules" -o json)"
HAS_R6="$(echo "$RULES_JSON" | grep -c '"name"[[:space:]]*:[[:space:]]*"r6"' || true)"

# Remove r6 if exists (we will rebuild full list)
if [[ "${HAS_R6:-0}" -gt 0 ]]; then
  RULES_JSON="$(echo "$RULES_JSON" | python - <<'PY'
import json,sys
rules=json.load(sys.stdin)
rules=[r for r in rules if r.get("name")!="r6"]
print(json.dumps(rules))
PY
)"
fi

# Ensure we still have r1..r5
for r in r1 r2 r3 r4 r5; do
  if ! echo "$RULES_JSON" | grep -q "\"name\"[[:space:]]*:[[:space:]]*\"$r\""; then
    echo "❌ Missing $r in policy customRules. Stop."
    echo "Rollback (git): git reset --hard HEAD~1"
    exit 2
  fi
done

URI_LIST='["/api/docs","/api/redoc","/openapi.json","/api/openapi.json"]'

# Append r6
NEW_RULES="$(python - <<PY
import json
rules=json.loads('''$RULES_JSON''')
rules.append({
  "name":"r6",
  "priority":60,
  "ruleType":"MatchRule",
  "action":"Block",
  "matchConditions":[
    {
      "matchVariables":[{"variableName":"RequestUri"}],
      "operator":"Contains",
      "matchValues": json.loads('''$URI_LIST'''),
      "negationConditon": False,
      "transforms":["Lowercase"]
    },
    {
      "matchVariables":[{"variableName":"RequestHeaders","selector":"User-Agent"}],
      "operator":"Equal",
      "matchValues":[""],
      "negationConditon": False
    }
  ]
})
print(json.dumps(rules))
PY
)"

az network application-gateway waf-policy update \
  -g "$RG" -n "$POLICY" \
  --set customRules="$NEW_RULES" \
  -o none

echo "✅ Added r6: block empty UA on docs/openapi"

az network application-gateway waf-policy show -g "$RG" -n "$POLICY" \
  --query "customRules[].{name:name,priority:priority,ruleType:ruleType,action:action}" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
