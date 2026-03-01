#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Fix Scheduled Query Alerts syntax (condition + condition-query placeholders)
# ID: CC_PATCH_MONITOR_ALERTS_WAF_V3_FIX_CONDITIONQUERY_20260301
# ============================

RG="rg-colconnect-prod-frc"
LAW="law-colconnect-prod-frc"
AG="ag-colconnect-prod-alerts"
ALERT_EMAIL="ton.email@domaine.tld"  # <-- change

echo "== [CC_PATCH_MONITOR_ALERTS_WAF_V3_FIX_CONDITIONQUERY] Start =="

az account show -o none

echo "== CLI config: allow preview extensions + no prompt =="
az config set extension.use_dynamic_install=yes_without_prompt -o none || true
az config set extension.dynamic_install_allow_preview=true -o none || true

echo "== Ensure scheduled-query extension installed =="
az extension add -n scheduled-query -y -o none || az extension update -n scheduled-query -o none
echo "✅ scheduled-query extension ready"

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

# ----------------------------
# Alert 1: WAF blocks spike
# ----------------------------
echo "== Create/Update Alert: WAF blocks spike (>200 / 5m) =="

WAFBLOCKS_KQL='AzureDiagnostics
| where TimeGenerated > ago(5m)
| where ResourceType == "APPLICATIONGATEWAYS"
| where Category == "ApplicationGatewayFirewallLog"
| summarize blocks=count() by _ResourceId
| where blocks > 200'

# Condition syntax per az monitor scheduled-query docs:
# count 'Placeholder_1' > 0 resource id _ResourceId at least 1 violations out of 1 aggregated points
az monitor scheduled-query create \
  -g "$RG" -n "alert-waf-blocks-spike" \
  --scopes "$LAW_ID" \
  --description "WAF blocks spike >200/5m" \
  --severity 2 \
  --enabled true \
  --evaluation-frequency "PT5M" \
  --window-size "PT5M" \
  --condition "count 'WAFBLOCKS' > 0 resource id _ResourceId at least 1 violations out of 1 aggregated points" \
  --condition-query WAFBLOCKS="$WAFBLOCKS_KQL" \
  --action-groups "$AG_ID" \
  -o none

echo "✅ alert-waf-blocks-spike set"

# ----------------------------
# Alert 2: RateLimit spike (r3)
# ----------------------------
echo "== Create/Update Alert: RateLimit spike (>50 / 5m) =="

RATELIMIT_KQL='AzureDiagnostics
| where TimeGenerated > ago(5m)
| where ResourceType == "APPLICATIONGATEWAYS"
| where Category == "ApplicationGatewayFirewallLog"
| where ruleId_s has "r3" or message_s has "RateLimit" or details_message_s has "RateLimit"
| summarize hits=count() by _ResourceId
| where hits > 50'

az monitor scheduled-query create \
  -g "$RG" -n "alert-waf-ratelimit-spike" \
  --scopes "$LAW_ID" \
  --description "RateLimit spike >50/5m" \
  --severity 2 \
  --enabled true \
  --evaluation-frequency "PT5M" \
  --window-size "PT5M" \
  --condition "count 'RATELIMIT' > 0 resource id _ResourceId at least 1 violations out of 1 aggregated points" \
  --condition-query RATELIMIT="$RATELIMIT_KQL" \
  --action-groups "$AG_ID" \
  -o none

echo "✅ alert-waf-ratelimit-spike set"

echo ""
echo "== Verify scheduled-query rules =="
az monitor scheduled-query list -g "$RG" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
