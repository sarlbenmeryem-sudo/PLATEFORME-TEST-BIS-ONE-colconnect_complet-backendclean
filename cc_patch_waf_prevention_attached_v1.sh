#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: WAF -> Prevention on attached policy
# ID: CC_PATCH_WAF_PREVENTION_ATTACHED_V1_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

need() { command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing $1" >&2; exit 1; }; }
need az

az account show -o none

policy_id="$(az network application-gateway show -g "$RG" -n "$APPGW" --query "firewallPolicy.id" -o tsv)"
policy_name="$(echo "$policy_id" | awk -F/ '{print $NF}')"

echo "== Policy: $policy_name =="

az network application-gateway waf-policy policy-setting update \
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
