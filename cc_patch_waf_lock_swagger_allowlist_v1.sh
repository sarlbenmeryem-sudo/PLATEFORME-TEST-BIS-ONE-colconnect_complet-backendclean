#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Lock Swagger/OpenAPI to IP allowlist (r4 allow, r5 block)
# ID: CC_PATCH_WAF_LOCK_SWAGGER_ALLOWLIST_V1_20260301
# ============================

RG="rg-colconnect-prod-frc"
POLICY="wafp-colconnect-prod"

# ✅ Mets ton IP publique ici (ex: "203.0.113.4/32"). Tu peux mettre plusieurs CIDR.
ALLOWED_IPS_CIDR=("1.2.3.4/32")

echo "== [CC_PATCH_WAF_LOCK_SWAGGER_ALLOWLIST_V1] Start =="

az account show -o none
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" -o none

# Build JSON array for matchValues
IPS_JSON="$(printf '"%s",' "${ALLOWED_IPS_CIDR[@]}")"
IPS_JSON="[${IPS_JSON%,}]"

echo "Allowed IPs JSON: $IPS_JSON"

echo "== Fetch existing r1 r2 r3 =="
R1="$(az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query "customRules[?name=='r1'] | [0]" -o json)"
R2="$(az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query "customRules[?name=='r2'] | [0]" -o json)"
R3="$(az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query "customRules[?name=='r3'] | [0]" -o json)"

for n in R1 R2 R3; do
  if [[ "${!n}" == "null" || -z "${!n}" ]]; then
    echo "❌ Missing $n. Stop."
    echo "Rollback (git): git reset --hard HEAD~1"
    exit 2
  fi
done

echo "✅ r1 r2 r3 found"

echo ""
echo "== Apply customRules atomically: r1+r2+r3 + r4(allow) + r5(block) =="

az network application-gateway waf-policy update \
  -g "$RG" -n "$POLICY" \
  --set customRules="[
    $R1,
    $R2,
    $R3,
    {
      \"name\": \"r4\",
      \"priority\": 40,
      \"ruleType\": \"MatchRule\",
      \"action\": \"Allow\",
      \"matchConditions\": [
        {
          \"matchVariables\": [{\"variableName\":\"RequestUri\"}],
          \"operator\":\"Contains\",
          \"matchValues\":[\"/api/docs\",\"/api/redoc\",\"/openapi.json\"],
          \"negationConditon\": false,
          \"transforms\":[\"Lowercase\"]
        },
        {
          \"matchVariables\": [{\"variableName\":\"RemoteAddr\"}],
          \"operator\":\"IPMatch\",
          \"matchValues\": $IPS_JSON,
          \"negationConditon\": false
        }
      ]
    },
    {
      \"name\": \"r5\",
      \"priority\": 50,
      \"ruleType\": \"MatchRule\",
      \"action\": \"Block\",
      \"matchConditions\": [
        {
          \"matchVariables\": [{\"variableName\":\"RequestUri\"}],
          \"operator\":\"Contains\",
          \"matchValues\":[\"/api/docs\",\"/api/redoc\",\"/openapi.json\"],
          \"negationConditon\": false,
          \"transforms\":[\"Lowercase\"]
        }
      ]
    }
  ]" \
  -o none

echo "✅ Swagger/OpenAPI locked (r4 allowlist, r5 block)"

echo ""
echo "== Verify rules =="
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" \
  --query "customRules[].{name:name,priority:priority,ruleType:ruleType,action:action}" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
