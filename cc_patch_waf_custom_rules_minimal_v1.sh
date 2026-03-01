#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: WAF custom rules (geo/bot/rate limit) minimal safe
# ID: CC_PATCH_WAF_CUSTOM_RULES_MINIMAL_V1_20260301
# ============================

RG="rg-colconnect-prod-frc"
POLICY="wafp-colconnect-prod"

echo "== [CC_PATCH_WAF_CUSTOM_RULES_MINIMAL_V1] Start =="

az account show -o none

echo "== Ensure policy exists =="
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" -o none

# Helpers
upsert_match_rule () {
  local name="$1"
  local priority="$2"
  local match_conditions="$3"

  if az network application-gateway waf-policy custom-rule show -g "$RG" --policy-name "$POLICY" -n "$name" >/dev/null 2>&1; then
    az network application-gateway waf-policy custom-rule delete -g "$RG" --policy-name "$POLICY" -n "$name" -o none
    echo "ℹ️ Recreating custom rule: $name"
  fi

  az network application-gateway waf-policy custom-rule create \
    -g "$RG" --policy-name "$POLICY" -n "$name" \
    --priority "$priority" \
    --rule-type MatchRule \
    --action Block \
    --match-conditions "$match_conditions" \
    -o none

  echo "✅ Rule applied: $name"
}

echo ""
echo "== Rule 10: Block obvious scanners by User-Agent (low false positives) =="
upsert_match_rule \
  "block-obvious-scanners-ua" \
  "10" \
  "matchVariables=[{variableName=RequestHeaders,selector=User-Agent}],operator=Contains,matchValues=[sqlmap,nmap,nikto,gobuster,dirbuster,wpscan,acunetix,nessus,openvas,zgrab,python-requests],negationConditon=false,transforms=[Lowercase]"

echo ""
echo "== Rule 20: Block common bad paths (wp-admin, .env, etc.) =="
upsert_match_rule \
  "block-bad-paths" \
  "20" \
  "matchVariables=[{variableName=RequestUri}],operator=Contains,matchValues=[/wp-admin,/wp-login,.env,/.git,/phpmyadmin,/cgi-bin],negationConditon=false,transforms=[Lowercase]"

echo ""
echo "== OPTIONAL Rule 30: Geo-block non-EU (only if CLI supports GeoMatch) =="
HELP_TXT="$(az network application-gateway waf-policy custom-rule create -h 2>/dev/null || true)"
if echo "$HELP_TXT" | grep -qi "GeoMatch"; then
  # EU/EEA minimal set (adjust later)
  if az network application-gateway waf-policy custom-rule show -g "$RG" --policy-name "$POLICY" -n "block-non-eu" >/dev/null 2>&1; then
    az network application-gateway waf-policy custom-rule delete -g "$RG" --policy-name "$POLICY" -n "block-non-eu" -o none
  fi

  az network application-gateway waf-policy custom-rule create \
    -g "$RG" --policy-name "$POLICY" -n "block-non-eu" \
    --priority 30 \
    --rule-type MatchRule \
    --action Block \
    --match-conditions "matchVariables=[{variableName=RemoteAddr}],operator=GeoMatch,matchValues=[US,RU,CN,BR,IN,TR,UA,IR,PK],negationConditon=false" \
    -o none

  echo "✅ Rule applied: block-non-eu (sample blocklist countries)"
else
  echo "ℹ️ GeoMatch not supported by this CLI/version -> skipping geo rule"
fi

echo ""
echo "== OPTIONAL Rule 40: Rate limit /api/ (only if rule-type RateLimitRule exists) =="
if echo "$HELP_TXT" | grep -qi "RateLimitRule"; then
  if az network application-gateway waf-policy custom-rule show -g "$RG" --policy-name "$POLICY" -n "ratelimit-api" >/dev/null 2>&1; then
    az network application-gateway waf-policy custom-rule delete -g "$RG" --policy-name "$POLICY" -n "ratelimit-api" -o none
  fi

  az network application-gateway waf-policy custom-rule create \
    -g "$RG" --policy-name "$POLICY" -n "ratelimit-api" \
    --priority 40 \
    --rule-type RateLimitRule \
    --action Block \
    --rate-limit-duration OneMin \
    --rate-limit-threshold 200 \
    --group-by-user-session "ClientAddr" \
    --match-conditions "matchVariables=[{variableName=RequestUri}],operator=BeginsWith,matchValues=[/api/],negationConditon=false" \
    -o none

  echo "✅ Rule applied: ratelimit-api"
else
  echo "ℹ️ RateLimitRule not supported by this CLI/version -> skipping rate limit"
fi

echo ""
echo "== Verify custom rules =="
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query "customRules[].{name:name,priority:priority,ruleType:ruleType,action:action}" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
