#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: WAF migrate Microsoft_DefaultRuleSet 2.1 -> OWASP 3.2 + Prevention
# ID: CC_PATCH_APPGW_WAF_MIGRATE_TO_OWASP32_V5_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"
POLICY="wafp-colconnect-prod"

MAX_REQ_BODY_KB="128"
FILE_UPLOAD_MB="50"

echo "== [CC_PATCH_APPGW_WAF_MIGRATE_TO_OWASP32_V5] Start =="

az account show -o none

echo "== Ensure WAF policy exists =="
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" -o none

echo ""
echo "== Snapshot current managed rule sets (before) =="
az network application-gateway waf-policy managed-rule rule-set list \
  -g "$RG" --policy-name "$POLICY" -o jsonc

echo ""
echo "== Remove Microsoft_DefaultRuleSet 2.1 (primary) =="
# This removes the current primary ruleset so we can add OWASP as primary
set +e
RM_OUT="$(az network application-gateway waf-policy managed-rule rule-set remove \
  -g "$RG" --policy-name "$POLICY" \
  --type Microsoft_DefaultRuleSet --version 2.1 2>&1)"
RM_RC=$?
set -e

if [[ $RM_RC -ne 0 ]]; then
  echo "❌ Failed to remove Microsoft_DefaultRuleSet 2.1"
  echo "$RM_OUT"
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi
echo "✅ Removed Microsoft_DefaultRuleSet 2.1"

echo ""
echo "== Add OWASP 3.2 as primary =="
az network application-gateway waf-policy managed-rule rule-set add \
  -g "$RG" --policy-name "$POLICY" \
  --type OWASP --version 3.2 -o none
echo "✅ Added OWASP 3.2"

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
echo "== Attach policy to AppGW (ensure) =="
POLICY_ID="$(az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query id -o tsv)"
az network application-gateway update -g "$RG" -n "$APPGW" --set firewallPolicy.id="$POLICY_ID" -o none

echo ""
echo "== Verify managed rule sets (after) =="
az network application-gateway waf-policy managed-rule rule-set list \
  -g "$RG" --policy-name "$POLICY" -o table

echo ""
echo "== Verify policy summary =="
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" \
  --query "{mode:policySettings.mode,requestBodyCheck:policySettings.requestBodyCheck,maxRequestBodySizeInKb:policySettings.maxRequestBodySizeInKb,fileUploadLimitInMb:policySettings.fileUploadLimitInMb,managedRuleSets:managedRules.managedRuleSets[].{type:ruleSetType,version:ruleSetVersion}}" -o jsonc

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
