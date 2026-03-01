#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Log Analytics Alerts (WAF blocks + RateLimit spikes)
# ID: CC_PATCH_MONITOR_ALERTS_WAF_V1_20260301
# ============================

RG="rg-colconnect-prod-frc"
LAW="law-colconnect-prod-frc"
AG="ag-colconnect-prod-alerts"
ALERT_EMAIL="ton.email@domaine.tld"  # <-- change

echo "== [CC_PATCH_MONITOR_ALERTS_WAF_V1] Start =="

az account show -o none

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

echo "== Create/Update Alert: WAF blocks spike (5m) =="

Q1='AzureDiagnostics
| where ResourceType == "APPLICATIONGATEWAYS"
| where Category == "ApplicationGatewayFirewallLog"
| summarize blocks=count() by bin(TimeGenerated, 5m)
| where blocks > 200'

az monitor scheduled-query create \
  -g "$RG" -n "alert-waf-blocks-spike" \
  --scopes "$LAW_ID" \
  --description "WAF blocks spike >200/5m" \
  --severity 2 \
  --enabled true \
  --evaluation-frequency "PT5M" \
  --window-size "PT5M" \
  --condition "count > 0" \
  --query "$Q1" \
  --action-groups "$AG_ID" \
  -o none

echo "✅ alert-waf-blocks-spike set"

echo "== Create/Update Alert: RateLimit hits spike (5m) =="

Q2='AzureDiagnostics
| where ResourceType == "APPLICATIONGATEWAYS"
| where Category == "ApplicationGatewayFirewallLog"
| where message_s has "RateLimit" or details_message_s has "RateLimit" or ruleId_s has "r3"
| summarize hits=count() by bin(TimeGenerated, 5m)
| where hits > 50'

az monitor scheduled-query create \
  -g "$RG" -n "alert-waf-ratelimit-spike" \
  --scopes "$LAW_ID" \
  --description "RateLimit spike >50/5m" \
  --severity 2 \
  --enabled true \
  --evaluation-frequency "PT5M" \
  --window-size "PT5M" \
  --condition "count > 0" \
  --query "$Q2" \
  --action-groups "$AG_ID" \
  -o none

echo "✅ alert-waf-ratelimit-spike set"

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
