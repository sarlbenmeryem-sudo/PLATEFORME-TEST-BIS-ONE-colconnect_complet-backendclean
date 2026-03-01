#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Enable WAF policy attached to AppGW (Detection, Enabled)
# ID: CC_PATCH_WAF_ENABLE_ATTACHED_POLICY_V1_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

WAF_MODE="Detection"
CRS_TRY=("3.3" "3.2")

echo "== [CC_PATCH_WAF_ENABLE_ATTACHED_POLICY_V1_20260301] Start =="

need() { command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing $1" >&2; exit 1; }; }
need az
need jq

az account show -o none

# Retry wrapper for transient Azure errors (including AppGW busy)
az_retry() {
  local max=14
  local n=1
  local delay=8
  while true; do
    set +e
    out="$("$@" 2>&1)"
    code=$?
    set -e
    if [[ $code -eq 0 ]]; then
      return 0
    fi
    if echo "$out" | grep -Eqi "PutApplicationGatewayOperation|Another operation is in progress|OperationPreempted|was being modified|TooManyRequests|429|timeout|temporar|Transient"; then
      if [[ $n -ge $max ]]; then
        echo "❌ Retry exhausted ($max). Last error:" >&2
        echo "$out" >&2
        return 1
      fi
      echo "⏳ Azure transient error (retry $n/$max) in ${delay}s..."
      sleep "$delay"
      n=$((n+1))
      delay=$((delay+5))
      continue
    fi
    echo "❌ Azure command failed:" >&2
    echo "$out" >&2
    return 1
  done
}

echo ""
echo "== [1] Detect firewallPolicy attached to AppGW =="
policy_id="$(az network application-gateway show -g "$RG" -n "$APPGW" --query "firewallPolicy.id" -o tsv || true)"
if [[ -z "${policy_id:-}" || "$policy_id" == "null" ]]; then
  echo "❌ AppGW has no firewallPolicy.id attached. Stop." >&2
  exit 1
fi
echo "Attached policy id: $policy_id"

policy_name="$(echo "$policy_id" | awk -F/ '{print $NF}')"
if [[ -z "${policy_name:-}" ]]; then
  echo "❌ Cannot parse policy name from id" >&2
  exit 1
fi
echo "Attached policy name: $policy_name"

echo ""
echo "== [2] Ensure policy exists & show current settings =="
az network application-gateway waf-policy show -g "$RG" -n "$policy_name" --query "{mode:policySettings.mode,state:policySettings.state}" -o table || true

echo ""
echo "== [3] Ensure OWASP CRS is present (best effort) =="
# We check if any managed rules exist; if not, add CRS
has_rules="$(az network application-gateway waf-policy show -g "$RG" -n "$policy_name" --query "managedRules.managedRuleSets | length(@)" -o tsv 2>/dev/null || echo "0")"
if [[ "${has_rules:-0}" == "0" ]]; then
  echo "No managedRuleSets detected -> adding OWASP CRS"
  crs_ok="no"
  for crs in "${CRS_TRY[@]}"; do
    echo "-- Trying CRS $crs --"
    set +e
    out="$(az network application-gateway waf-policy managed-rule rule-set add \
      -g "$RG" --policy-name "$policy_name" \
      --type OWASP --version "$crs" -o none 2>&1)"
    code=$?
    set -e
    if [[ $code -eq 0 ]]; then
      crs_ok="yes"
      echo "✅ CRS enabled: OWASP $crs"
      break
    else
      echo "⚠️ CRS $crs not applied. First lines:"
      echo "$out" | sed -n '1,10p'
    fi
  done
  if [[ "$crs_ok" != "yes" ]]; then
    echo "❌ Could not enable OWASP CRS (tried: ${CRS_TRY[*]})." >&2
    exit 1
  fi
else
  echo "✅ ManagedRuleSets already present ($has_rules) -> keep as-is"
fi

echo ""
echo "== [4] Set policy state=Enabled and mode=Detection =="
az_retry az network application-gateway waf-policy policy-setting update \
  -g "$RG" --policy-name "$policy_name" \
  --mode "$WAF_MODE" \
  --state Enabled \
  --request-body-check true \
  --max-request-body-size-in-kb 128 \
  --file-upload-limit-in-mb 100 \
  -o none

echo ""
echo "== [5] Confirm policy settings =="
az network application-gateway waf-policy show -g "$RG" -n "$policy_name" --query "{mode:policySettings.mode,state:policySettings.state}" -o table

echo ""
echo "== [6] Confirm AppGW association still points to same policy =="
az network application-gateway show -g "$RG" -n "$APPGW" --query "firewallPolicy.id" -o tsv

echo ""
echo "== Rollback Git (1 step) =="
echo "git reset --hard HEAD~1"

echo ""
echo "== [CC_PATCH_WAF_ENABLE_ATTACHED_POLICY_V1_20260301] Done =="
