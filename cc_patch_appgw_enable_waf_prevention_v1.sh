#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"
POLICY="wafp-colconnect-prod"

echo "== [CC_PATCH_APPGW_ENABLE_WAF_PREVENTION_V1] Start =="

echo "== Create/Update WAF Policy =="
if az network application-gateway waf-policy show -g "$RG" -n "$POLICY" >/dev/null 2>&1; then
  echo "✅ WAF policy exists: $POLICY"
else
  az network application-gateway waf-policy create -g "$RG" -n "$POLICY" -o none
  echo "✅ Created WAF policy: $POLICY"
fi

echo ""
echo "== Set policy in PREVENTION + OWASP ruleset =="
# OWASP 3.2 (standard)
az network application-gateway waf-policy managed-rule set add \
  -g "$RG" --policy-name "$POLICY" \
  --type OWASP --version 3.2 -o none || true

# Policy settings: prevention + body check + limits
az network application-gateway waf-policy policy-setting update \
  -g "$RG" --policy-name "$POLICY" \
  --mode Prevention \
  --request-body-check true \
  --max-request-body-size-in-kb 128 \
  --file-upload-limit-in-mb 50 \
  -o none

echo ""
echo "== Attach WAF policy to App Gateway =="
az network application-gateway update \
  -g "$RG" -n "$APPGW" \
  --set firewallPolicy.id="$(az network application-gateway waf-policy show -g "$RG" -n "$POLICY" --query id -o tsv)" \
  -o none

echo "✅ WAF PREVENTION enabled and attached to AppGW"

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
