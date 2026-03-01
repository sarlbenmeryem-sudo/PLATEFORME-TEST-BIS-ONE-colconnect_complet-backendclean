#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: WAF set OWASP 3.2 as sole primary ruleset (atomic managedRules swap)
# ID: CC_PATCH_APPGW_WAF_SET_OWASP32_ATOMIQUE_V6_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"
POLICY="wafp-colconnect-prod"

MAX_REQ_BODY_KB="128"
FILE_UPLOAD_MB="50"

echo "== [CC_PATCH_APPGW_WAF_SET_OWASP32_ATOMIQUE_V6] Start =="

az account show -o none

echo "== Show current managed rule sets (before) =="
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query "managedRules.managedRuleSets" -o jsonc

echo ""
echo "== Atomically set managedRules.managedRuleSets = [OWASP 3.2] =="
# This avoids invalid intermediate state (no primary ruleset).
az network application-gateway waf-policy update \
  -g "$RG" -n "$POLICY" \
  --set managedRules.exclusions="[]" \
  --set managedRules.managedRuleSets="[{\"ruleSetType\":\"OWASP\",\"ruleSetVersion\":\"3.2\",\"ruleGroupOverrides\":[]}]" \
  -o none

echo ""
echo "== Set policy mode: Prevention + body check + limits =="
az network application-gateway waf-policy update \
  -g "$RG" -n "$POLICY" \
  --set policySettings.mode="Prevention" \
  --set policySettings.requestBodyCheck=true \
  --set policySettings.maxRequestBodySizeInKb="$MAX_REQ_BODY_KB" \
  --set policySettings.fileUploadLimitInMb="$FILE_UPLOAD_MB" \
  -o none

echo ""
echo "== Re-attach policy to AppGW (ensure) =="
POLICY_ID="$(az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query id -o tsv)"
az network application-gateway update -g "$RG" -n "$APPGW" --set firewallPolicy.id="$POLICY_ID" -o none

echo ""
echo "== Verify (after) =="
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" \
  --query "{mode:policySettings.mode,managedRuleSets:managedRules.managedRuleSets[].{type:ruleSetType,version:ruleSetVersion}}" -o jsonc

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
