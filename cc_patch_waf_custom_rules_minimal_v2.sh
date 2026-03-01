#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: WAF custom rules minimal (JSON match-conditions)
# ID: CC_PATCH_WAF_CUSTOM_RULES_MINIMAL_V2_20260301
# ============================

RG="rg-colconnect-prod-frc"
POLICY="wafp-colconnect-prod"

echo "== [CC_PATCH_WAF_CUSTOM_RULES_MINIMAL_V2] Start =="

az account show -o none
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" -o none

recreate_rule () {
  local name="$1"
  local priority="$2"
  local match_json="$3"

  if az network application-gateway waf-policy custom-rule show -g "$RG" --policy-name "$POLICY" -n "$name" >/dev/null 2>&1; then
    az network application-gateway waf-policy custom-rule delete -g "$RG" --policy-name "$POLICY" -n "$name" -o none
    echo "ℹ️ Deleted existing rule: $name"
  fi

  az network application-gateway waf-policy custom-rule create \
    -g "$RG" --policy-name "$POLICY" -n "$name" \
    --priority "$priority" \
    --rule-type MatchRule \
    --action Block \
    --match-conditions "$match_json" \
    -o none

  echo "✅ Created rule: $name"
}

echo ""
echo "== Rule 10: Block obvious scanners by User-Agent =="
recreate_rule "block-obvious-scanners-ua" "10" '[
  {
    "matchVariables": [
      { "variableName": "RequestHeaders", "selector": "User-Agent" }
    ],
    "operator": "Contains",
    "matchValues": [
      "sqlmap","nmap","nikto","gobuster","dirbuster","wpscan","acunetix","nessus","openvas","zgrab","python-requests"
    ],
    "negationConditon": false,
    "transforms": ["Lowercase"]
  }
]'

echo ""
echo "== Rule 20: Block common bad paths (.env/.git/wp-admin/phpmyadmin/cgi-bin) =="
recreate_rule "block-bad-paths" "20" '[
  {
    "matchVariables": [
      { "variableName": "RequestUri" }
    ],
    "operator": "Contains",
    "matchValues": [
      "/wp-admin","/wp-login",".env","/.git","/phpmyadmin","/cgi-bin"
    ],
    "negationConditon": false,
    "transforms": ["Lowercase"]
  }
]'

echo ""
echo "== Verify custom rules =="
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" \
  --query "customRules[].{name:name,priority:priority,ruleType:ruleType,action:action}" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
