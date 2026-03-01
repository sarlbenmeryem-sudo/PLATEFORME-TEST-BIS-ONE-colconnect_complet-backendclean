#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: WAF hardening (Prevention + OWASP 3.2 + basic bot block)
# ID: CC_PATCH_APPGW_WAF_HARDEN_V3_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"
POLICY="wafp-colconnect-prod"

# Policy tuning
MAX_REQ_BODY_KB="128"      # 128 KB
FILE_UPLOAD_MB="50"        # 50 MB

echo "== [CC_PATCH_APPGW_WAF_HARDEN_V3] Start =="

az account show -o none

echo "== Ensure WAF policy exists =="
if az network application-gateway waf-policy show -g "$RG" -n "$POLICY" >/dev/null 2>&1; then
  echo "✅ WAF policy exists: $POLICY"
else
  az network application-gateway waf-policy create -g "$RG" -n "$POLICY" -o none
  echo "✅ Created WAF policy: $POLICY"
fi

echo ""
echo "== Detect existing OWASP ruleset version =="
OWASP_VER="$(az network application-gateway waf-policy show -g "$RG" -n "$POLICY" \
  --query "managedRules.managedRuleSets[?ruleSetType=='OWASP'].ruleSetVersion | [0]" -o tsv || true)"

echo "Current OWASP_VER='${OWASP_VER:-}'"

if [[ -z "${OWASP_VER:-}" ]]; then
  echo "== Add OWASP 3.2 (no existing primary) =="
  az network application-gateway waf-policy managed-rule rule-set add \
    -g "$RG" --policy-name "$POLICY" \
    --type OWASP --version 3.2 -o none
  echo "✅ Added OWASP 3.2"
elif [[ "$OWASP_VER" != "3.2" ]]; then
  echo "== Update OWASP to 3.2 (avoid multiple primary rulesets) =="
  az network application-gateway waf-policy managed-rule rule-set update \
    -g "$RG" --policy-name "$POLICY" \
    --type OWASP --version 3.2 -o none
  echo "✅ Updated OWASP $OWASP_VER -> 3.2"
else
  echo "✅ OWASP already 3.2 (skip)"
fi

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
echo "== Upsert a basic custom rule: block obvious scanners by User-Agent =="
# NOTE: This is intentionally minimal to reduce false positives.
# If the rule already exists, we remove and recreate (idempotent).
RULE_NAME="block-obvious-scanners-ua"
if az network application-gateway waf-policy custom-rule show -g "$RG" --policy-name "$POLICY" -n "$RULE_NAME" >/dev/null 2>&1; then
  echo "Rule exists -> delete to recreate"
  az network application-gateway waf-policy custom-rule delete -g "$RG" --policy-name "$POLICY" -n "$RULE_NAME" -o none
fi

az network application-gateway waf-policy custom-rule create \
  -g "$RG" --policy-name "$POLICY" -n "$RULE_NAME" \
  --priority 10 \
  --rule-type MatchRule \
  --action Block \
  --match-conditions "matchVariables=[{variableName=RequestHeaders,selector=User-Agent}],operator=Contains,matchValues=[sqlmap,nmap,nikto,gobuster,dirbuster,wpscan,acunetix,nessus,openvas,zgrab,python-requests,curl],negationConditon=false,transforms=[Lowercase]" \
  -o none

echo "✅ Custom rule created: $RULE_NAME"

echo ""
echo "== Attach policy to AppGW (ensure) =="
POLICY_ID="$(az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query id -o tsv)"
az network application-gateway update -g "$RG" -n "$APPGW" --set firewallPolicy.id="$POLICY_ID" -o none
echo "✅ Attached: $POLICY_ID"

echo ""
echo "== Verify WAF effective settings =="
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" \
  --query "{mode:policySettings.mode,requestBodyCheck:policySettings.requestBodyCheck,maxRequestBodySizeInKb:policySettings.maxRequestBodySizeInKb,fileUploadLimitInMb:policySettings.fileUploadLimitInMb,owasp:managedRules.managedRuleSets[?ruleSetType=='OWASP'].ruleSetVersion | [0],customRules:customRules[].name}" -o jsonc

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
