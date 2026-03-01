#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: WAF custom rule (UA scanners) with strict alphanum name
# ID: CC_PATCH_WAF_RULE_UA_V5_20260301
# ============================

RG="rg-colconnect-prod-frc"
POLICY="wafp-colconnect-prod"

RULE="blockscannersua"   # alphanum only
PRIORITY="10"

echo "== [CC_PATCH_WAF_RULE_UA_V5] Start =="

az account show -o none
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" -o none

echo "== Recreate rule: $RULE =="

if az network application-gateway waf-policy custom-rule show -g "$RG" --policy-name "$POLICY" -n "$RULE" >/dev/null 2>&1; then
  az network application-gateway waf-policy custom-rule delete -g "$RG" --policy-name "$POLICY" -n "$RULE" -o none
  echo "ℹ️ Deleted existing rule: $RULE"
fi

az network application-gateway waf-policy custom-rule create \
  -g "$RG" --policy-name "$POLICY" -n "$RULE" \
  --priority "$PRIORITY" \
  --rule-type MatchRule \
  --action Block \
  -o none

echo "== Set matchConditions via update --set (AAZ-safe) =="
az network application-gateway waf-policy custom-rule update \
  -g "$RG" --policy-name "$POLICY" -n "$RULE" \
  --set matchConditions="[
    {
      \"matchVariables\": [
        {\"variableName\":\"RequestHeaders\",\"selector\":\"User-Agent\"}
      ],
      \"operator\":\"Contains\",
      \"matchValues\":[\"sqlmap\",\"nmap\",\"nikto\",\"gobuster\",\"dirbuster\",\"wpscan\",\"acunetix\",\"nessus\",\"openvas\",\"zgrab\",\"python-requests\"],
      \"negationConditon\": false,
      \"transforms\":[\"Lowercase\"]
    }
  ]" \
  -o none

echo "✅ Rule created & configured: $RULE"

echo ""
echo "== Verify custom rules =="
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" \
  --query "customRules[].{name:name,priority:priority,action:action,conditions:length(matchConditions)}" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
