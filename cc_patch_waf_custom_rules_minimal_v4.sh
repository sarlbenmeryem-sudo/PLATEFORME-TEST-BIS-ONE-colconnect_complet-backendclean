#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: WAF custom rules minimal (valid names + AAZ-safe update)
# ID: CC_PATCH_WAF_CUSTOM_RULES_MINIMAL_V4_20260301
# ============================

RG="rg-colconnect-prod-frc"
POLICY="wafp-colconnect-prod"

echo "== [CC_PATCH_WAF_CUSTOM_RULES_MINIMAL_V4] Start =="

az account show -o none
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" -o none

create_or_replace_rule () {
  local name="$1"
  local priority="$2"

  if az network application-gateway waf-policy custom-rule show -g "$RG" --policy-name "$POLICY" -n "$name" >/dev/null 2>&1; then
    az network application-gateway waf-policy custom-rule delete -g "$RG" --policy-name "$POLICY" -n "$name" -o none
    echo "ℹ️ Deleted existing rule: $name"
  fi

  az network application-gateway waf-policy custom-rule create \
    -g "$RG" --policy-name "$POLICY" -n "$name" \
    --priority "$priority" \
    --rule-type MatchRule \
    --action Block \
    -o none

  echo "✅ Created placeholder rule: $name"
}

echo ""
echo "== Rule 10: Block obvious scanners by User-Agent =="
RULE1="block_scanners_ua"
create_or_replace_rule "$RULE1" "10"

az network application-gateway waf-policy custom-rule update \
  -g "$RG" --policy-name "$POLICY" -n "$RULE1" \
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

echo "✅ Updated matchConditions for: $RULE1"

echo ""
echo "== Rule 20: Block common bad paths (.env/.git/wp-admin/phpmyadmin/cgi-bin) =="
RULE2="block_bad_paths"
create_or_replace_rule "$RULE2" "20"

az network application-gateway waf-policy custom-rule update \
  -g "$RG" --policy-name "$POLICY" -n "$RULE2" \
  --set matchConditions="[
    {
      \"matchVariables\": [
        {\"variableName\":\"RequestUri\"}
      ],
      \"operator\":\"Contains\",
      \"matchValues\":[\"/wp-admin\",\"/wp-login\",\".env\",\"/.git\",\"/phpmyadmin\",\"/cgi-bin\"],
      \"negationConditon\": false,
      \"transforms\":[\"Lowercase\"]
    }
  ]" \
  -o none

echo "✅ Updated matchConditions for: $RULE2"

echo ""
echo "== Verify custom rules =="
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" \
  --query "customRules[].{name:name,priority:priority,ruleType:ruleType,action:action,conditions:length(matchConditions)}" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
