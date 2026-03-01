#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: WAF hardening (Prevention + OWASP 3.2) [robust detection]
# ID: CC_PATCH_APPGW_WAF_HARDEN_V4_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"
POLICY="wafp-colconnect-prod"

MAX_REQ_BODY_KB="128"
FILE_UPLOAD_MB="50"

echo "== [CC_PATCH_APPGW_WAF_HARDEN_V4] Start =="

az account show -o none

echo "== Ensure WAF policy exists =="
if az network application-gateway waf-policy show -g "$RG" -n "$POLICY" >/dev/null 2>&1; then
  echo "✅ WAF policy exists: $POLICY"
else
  az network application-gateway waf-policy create -g "$RG" -n "$POLICY" -o none
  echo "✅ Created WAF policy: $POLICY"
fi

echo ""
echo "== Detect managed rule sets (raw) =="
# Grab JSON and detect OWASP presence via grep (avoids JMESPath surprises)
RULESETS_JSON="$(az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query "managedRules.managedRuleSets" -o json 2>/dev/null || echo "[]")"
echo "$RULESETS_JSON" | head -c 2000; echo ""

HAS_OWASP="false"
if echo "$RULESETS_JSON" | grep -q '"ruleSetType"[[:space:]]*:[[:space:]]*"OWASP"'; then
  HAS_OWASP="true"
fi
echo "HAS_OWASP=$HAS_OWASP"

echo ""
if [[ "$HAS_OWASP" == "true" ]]; then
  echo "== OWASP present -> update to 3.2 =="
  az network application-gateway waf-policy managed-rule rule-set update \
    -g "$RG" --policy-name "$POLICY" \
    --type OWASP --version 3.2 -o none
  echo "✅ Updated OWASP -> 3.2"
else
  echo "== OWASP not detected -> attempt add 3.2 (should only work if no primary exists) =="
  # If this fails again, it means there is another primary ruleset and we must UPDATE that one (ex: Microsoft_DefaultRuleSet / DRS).
  set +e
  ADD_OUT="$(az network application-gateway waf-policy managed-rule rule-set add \
    -g "$RG" --policy-name "$POLICY" \
    --type OWASP --version 3.2 2>&1)"
  ADD_RC=$?
  set -e
  if [[ $ADD_RC -ne 0 ]]; then
    echo "❌ Add OWASP failed. Output:"
    echo "$ADD_OUT"
    echo ""
    echo "== Listing managed rule sets (to identify the existing primary) =="
    az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query "managedRules.managedRuleSets[].{type:ruleSetType,version:ruleSetVersion}" -o table || true
    echo ""
    echo "STOP: Policy already has a primary ruleset but OWASP wasn't detected by grep/JMES."
    echo "We will not remove anything automatically (risk)."
    echo "Rollback (git): git reset --hard HEAD~1"
    exit 2
  fi
  echo "✅ Added OWASP 3.2"
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
echo "== Attach policy to AppGW (ensure) =="
POLICY_ID="$(az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query id -o tsv)"
az network application-gateway update -g "$RG" -n "$APPGW" --set firewallPolicy.id="$POLICY_ID" -o none
echo "✅ Attached: $POLICY_ID"

echo ""
echo "== Verify summary =="
az network application-gateway waf-policy show -g "$RG" -n "$POLICY" \
  --query "{mode:policySettings.mode,requestBodyCheck:policySettings.requestBodyCheck,maxRequestBodySizeInKb:policySettings.maxRequestBodySizeInKb,fileUploadLimitInMb:policySettings.fileUploadLimitInMb,managedRuleSets:managedRules.managedRuleSets[].{type:ruleSetType,version:ruleSetVersion}}" -o jsonc

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
