#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"
POLICY="wafp-colconnect-prod"

echo "== [CC_PATCH_APPGW_ENABLE_WAF_PREVENTION_V2] Start =="

az account show -o none

echo "== Ensure WAF Policy =="
if az network application-gateway waf-policy show -g "$RG" -n "$POLICY" >/dev/null 2>&1; then
  echo "✅ WAF policy exists: $POLICY"
else
  az network application-gateway waf-policy create -g "$RG" -n "$POLICY" -o none
  echo "✅ Created WAF policy: $POLICY"
fi

echo ""
echo "== Add OWASP rule-set (3.2) =="
# Correct CLI subcommand is: managed-rule rule-set add
az network application-gateway waf-policy managed-rule rule-set add \
  -g "$RG" --policy-name "$POLICY" \
  --type OWASP --version 3.2 -o none || true

echo ""
echo "== Policy settings: Prevention + body check + limits =="
az network application-gateway waf-policy policy-setting update \
  -g "$RG" --policy-name "$POLICY" \
  --mode Prevention \
  --request-body-check true \
  --max-request-body-size-in-kb 128 \
  --file-upload-limit-in-mb 50 \
  -o none

echo ""
echo "== Attach WAF policy to AppGW =="
POLICY_ID="$(az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query id -o tsv)"
az network application-gateway update -g "$RG" -n "$APPGW" --set firewallPolicy.id="$POLICY_ID" -o none

echo "✅ WAF Prevention enabled and attached"

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
