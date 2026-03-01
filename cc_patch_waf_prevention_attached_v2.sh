#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: WAF -> Prevention on AppGW attached policy (with retry)
# ID: CC_PATCH_WAF_PREVENTION_ATTACHED_V2_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing $1" >&2; exit 1; }; }
need az

az account show -o none

az_retry() {
  local max=12 n=1 delay=7
  while true; do
    set +e
    out="$("$@" 2>&1)"; code=$?
    set -e
    if [[ $code -eq 0 ]]; then return 0; fi
    if echo "$out" | grep -Eqi "PutApplicationGatewayOperation|Another operation is in progress|OperationPreempted|was being modified|TooManyRequests|429|timeout|temporar|Transient"; then
      if [[ $n -ge $max ]]; then
        echo "❌ Retry exhausted ($max). Last error:" >&2
        echo "$out" >&2
        return 1
      fi
      echo "⏳ Azure transient error (retry $n/$max) in ${delay}s..."
      sleep "$delay"; n=$((n+1)); delay=$((delay+5))
      continue
    fi
    echo "❌ Azure command failed:" >&2
    echo "$out" >&2
    return 1
  done
}

policy_id="$(az network application-gateway show -g "$RG" -n "$APPGW" --query "firewallPolicy.id" -o tsv)"
policy_name="$(echo "$policy_id" | awk -F/ '{print $NF}')"
if [[ -z "${policy_name:-}" ]]; then
  echo "❌ Cannot resolve attached WAF policy name" >&2
  exit 1
fi

echo "== Policy: $policy_name =="

az_retry az network application-gateway waf-policy policy-setting update \
  -g "$RG" --policy-name "$policy_name" \
  --mode Prevention \
  --state Enabled \
  -o none

az network application-gateway waf-policy show -g "$RG" -n "$policy_name" \
  --query "{mode:policySettings.mode,state:policySettings.state}" -o table

echo ""
echo "== Rollback Git (1 step) =="
echo "git reset --hard HEAD~1"

echo "== Done =="
