#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Create Scheduled Query Alert with minimal condition (parser-safe)
# ID: CC_PATCH_MONITOR_ALERTS_WAF_V7_CREATE_APIWAF_ALERT_MIN_CONDITION_20260301
# ============================

RG="rg-colconnect-prod-frc"
LAW="law-colconnect-prod-frc"
AG="ag-colconnect-prod-alerts"

ALERT_NAME="alert-waf-api-wafhits-spike"
THRESHOLD="80"
FREQ="PT5M"
WINDOW="PT5M"

echo "== [CC_PATCH_MONITOR_ALERTS_WAF_V7_CREATE_APIWAF_ALERT_MIN_CONDITION] Start =="

az account show -o none

echo "== Ensure extensions =="
az extension add -n scheduled-query -y -o none || az extension update -n scheduled-query -o none

echo "== Resolve LAW IDs =="
LAW_RESID="$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query id -o tsv)"
if [[ -z "${LAW_RESID:-}" ]]; then
  echo "❌ Cannot resolve LAW resourceId"
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi

echo "== Resolve Action Group ID =="
AG_ID="$(az monitor action-group show -g "$RG" -n "$AG" --query id -o tsv)"
if [[ -z "${AG_ID:-}" ]]; then
  echo "❌ Cannot resolve Action Group ID: $AG"
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi

echo "== Delete existing alert if present =="
if az monitor scheduled-query show -g "$RG" -n "$ALERT_NAME" >/dev/null 2>&1; then
  az monitor scheduled-query delete -g "$RG" -n "$ALERT_NAME" -o none
  echo "ℹ️ Deleted existing: $ALERT_NAME"
fi

echo ""
echo "== Create alert: WAF firewall log entries on /api/ > ${THRESHOLD} in 5m =="

API_WAFHITS_KQL="AzureDiagnostics
| where TimeGenerated > ago(5m)
| where ResourceType == 'APPLICATIONGATEWAYS'
| where Category == 'ApplicationGatewayFirewallLog'
| where requestUri_s startswith '/api/'
| summarize hits=count() by _ResourceId
| where hits > ${THRESHOLD}"

# ✅ Minimal condition (parser-safe across scheduled-query preview builds)
# Trigger if query returns at least one row.
az monitor scheduled-query create \
  -g "$RG" -n "$ALERT_NAME" \
  --scopes "$LAW_RESID" \
  --severity 2 \
  --evaluation-frequency "$FREQ" \
  --window-size "$WINDOW" \
  --condition "count 'APIWAF' > 0" \
  --condition-query APIWAF="$API_WAFHITS_KQL" \
  --action-groups "$AG_ID" \
  -o none

echo "✅ Created: $ALERT_NAME"

echo ""
echo "== Verify scheduled-query rules =="
az monitor scheduled-query list -g "$RG" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
