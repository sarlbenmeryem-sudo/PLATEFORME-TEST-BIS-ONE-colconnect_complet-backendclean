#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Scheduled Query Alerts (compat scheduled-query 1.0.0b2)
# ID: CC_PATCH_MONITOR_ALERTS_WAF_V4_COMPAT_20260301
# ============================

RG="rg-colconnect-prod-frc"
LAW="law-colconnect-prod-frc"
AG="ag-colconnect-prod-alerts"
ALERT_EMAIL="ton.email@domaine.tld"  # <-- change

echo "== [CC_PATCH_MONITOR_ALERTS_WAF_V4_COMPAT] Start =="

az account show -o none

echo "== Ensure scheduled-query extension installed =="
az extension add -n scheduled-query -y -o none || az extension update -n scheduled-query -o none

LAW_ID="$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query id -o tsv)"
if [[ -z "${LAW_ID:-}" ]]; then
  echo "❌ Cannot resolve LAW_ID"
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi

echo "== Ensure Action Group exists =="
if az monitor action-group show -g "$RG" -n "$AG" >/dev/null 2>&1; then
  echo "✅ Action Group exists: $AG"
else
  az monitor action-group create -g "$RG" -n "$AG" \
    --short-name "CCALRT" \
    --action email ccops "$ALERT_EMAIL" \
    -o none
  echo "✅ Created Action Group: $AG"
fi
AG_ID="$(az monitor action-group show -g "$RG" -n "$AG" --query id -o tsv)"

# Helper: delete if exists (so we can recreate with compatible flags)
delete_if_exists () {
  local name="$1"
  if az monitor scheduled-query show -g "$RG" -n "$name" >/dev/null 2>&1; then
    az monitor scheduled-query delete -g "$RG" -n "$name" -o none
    echo "ℹ️ Deleted existing: $name"
  fi
}

# ----------------------------
# Alert 1: WAF blocks spike
# ----------------------------
AL1="alert-waf-blocks-spike"
delete_if_exists "$AL1"

WAFBLOCKS_KQL='AzureDiagnostics
| where TimeGenerated > ago(5m)
| where ResourceType == "APPLICATIONGATEWAYS"
| where Category == "ApplicationGatewayFirewallLog"
| summarize blocks=count() by _ResourceId
| where blocks > 200'

az monitor scheduled-query create \
  -g "$RG" -n "$AL1" \
  --scopes "$LAW_ID" \
  --severity 2 \
  --evaluation-frequency "PT5M" \
  --window-size "PT5M" \
  --condition "count 'WAFBLOCKS' > 0 resource id _ResourceId at least 1 violations out of 1 aggregated points" \
  --condition-query WAFBLOCKS="$WAFBLOCKS_KQL" \
  --action-groups "$AG_ID" \
  -o none

echo "✅ Created: $AL1"

# ----------------------------
# Alert 2: RateLimit spike
# ----------------------------
AL2="alert-waf-ratelimit-spike"
delete_if_exists "$AL2"

RATELIMIT_KQL='AzureDiagnostics
| where TimeGenerated > ago(5m)
| where ResourceType == "APPLICATIONGATEWAYS"
| where Category == "ApplicationGatewayFirewallLog"
| where ruleId_s has "r3" or message_s has "RateLimit" or details_message_s has "RateLimit"
| summarize hits=count() by _ResourceId
| where hits > 50'

az monitor scheduled-query create \
  -g "$RG" -n "$AL2" \
  --scopes "$LAW_ID" \
  --severity 2 \
  --evaluation-frequency "PT5M" \
  --window-size "PT5M" \
  --condition "count 'RATELIMIT' > 0 resource id _ResourceId at least 1 violations out of 1 aggregated points" \
  --condition-query RATELIMIT="$RATELIMIT_KQL" \
  --action-groups "$AG_ID" \
  -o none

echo "✅ Created: $AL2"

echo ""
echo "== Verify scheduled-query rules =="
az monitor scheduled-query list -g "$RG" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
