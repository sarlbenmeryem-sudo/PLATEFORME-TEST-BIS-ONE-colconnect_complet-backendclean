#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: WAF Swagger allowlist also covers /api/openapi.json
# ID: CC_PATCH_WAF_SWAGGER_ADD_API_OPENAPI_V1_20260301
# ============================

RG="rg-colconnect-prod-frc"
POLICY="wafp-colconnect-prod"

echo "== [CC_PATCH_WAF_SWAGGER_ADD_API_OPENAPI_V1] Start =="

az account show -o none
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" -o none

R1="$(az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query "customRules[?name=='r1'] | [0]" -o json)"
R2="$(az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query "customRules[?name=='r2'] | [0]" -o json)"
R3="$(az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query "customRules[?name=='r3'] | [0]" -o json)"
R4="$(az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query "customRules[?name=='r4'] | [0]" -o json)"
R5="$(az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query "customRules[?name=='r5'] | [0]" -o json)"

for n in R1 R2 R3 R4 R5; do
  if [[ "${!n}" == "null" || -z "${!n}" ]]; then
    echo "❌ Missing $n. Stop."
    echo "Rollback (git): git reset --hard HEAD~1"
    exit 2
  fi
done

# Update r4/r5 matchValues list by re-setting them atomically
# We keep existing r4 IP allowlist condition as-is by reusing $R4 object and only patching its uri list via string replace is risky,
# so we rebuild r4/r5 cleanly:
# - r4: Allow if URI in list AND RemoteAddr in allowlist
# - r5: Block if URI in list

# Extract allowed IPs from r4
IPS_JSON="$(az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query "customRules[?name=='r4'].matchConditions[?operator=='IPMatch'].matchValues | [0]" -o json)"
if [[ -z "${IPS_JSON:-}" || "${IPS_JSON}" == "null" ]]; then
  echo "❌ Cannot extract allowlist IPs from r4. Stop."
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi

URI_LIST='["/api/docs","/api/redoc","/openapi.json","/api/openapi.json"]'

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
          \"matchValues\": $URI_LIST,
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
          \"matchValues\": $URI_LIST,
          \"negationConditon\": false,
          \"transforms\":[\"Lowercase\"]
        }
      ]
    }
  ]" \
  -o none

echo "✅ Updated r4/r5 to include /api/openapi.json"

az network application-gateway waf-policy show -g "$RG" -n "$POLICY" \
  --query "customRules[].{name:name,priority:priority,ruleType:ruleType,action:action}" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
