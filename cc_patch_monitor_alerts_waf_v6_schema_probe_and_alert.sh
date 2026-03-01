#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Log Analytics schema probe + RateLimit proxy alert without action_s/ruleId_s
# ID: CC_PATCH_MONITOR_ALERTS_WAF_V6_SCHEMA_PROBE_AND_ALERT_20260301
# ============================

RG="rg-colconnect-prod-frc"
LAW="law-colconnect-prod-frc"
AG="ag-colconnect-prod-alerts"

# Alert tuning
THRESHOLD="80"        # number of WAF firewall log entries on /api/ within 5 minutes
WINDOW="PT5M"
FREQ="PT5M"
ALERT_NAME="alert-waf-api-wafhits-spike"

echo "== [CC_PATCH_MONITOR_ALERTS_WAF_V6_SCHEMA_PROBE_AND_ALERT] Start =="

az account show -o none

echo "== Ensure extensions =="
az extension add -n scheduled-query -y -o none || az extension update -n scheduled-query -o none
az extension add -n log-analytics -y -o none || az extension update -n log-analytics -o none

echo "== Resolve Log Analytics workspace identifiers =="
LAW_CUSTID="$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query customerId -o tsv)"
LAW_RESID="$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query id -o tsv)"

if [[ -z "${LAW_CUSTID:-}" || -z "${LAW_RESID:-}" ]]; then
  echo "❌ Cannot resolve LAW customerId or resourceId"
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi
echo "LAW customerId: $LAW_CUSTID"
echo "LAW resourceId: $LAW_RESID"

echo "== Resolve Action Group ID =="
AG_ID="$(az monitor action-group show -g "$RG" -n "$AG" --query id -o tsv)"
if [[ -z "${AG_ID:-}" ]]; then
  echo "❌ Cannot resolve Action Group ID: $AG"
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi
echo "AG_ID: $AG_ID"

echo ""
echo "== Probe WAF log schema (ApplicationGatewayFirewallLog) =="
# getschema returns columns for the query result; very useful to see real field names
az monitor log-analytics query \
  --workspace "$LAW_CUSTID" \
  --analytics-query "AzureDiagnostics | where Category == 'ApplicationGatewayFirewallLog' | getschema" \
  -o table || true

echo ""
echo "== Probe one sample record (last 24h) =="
az monitor log-analytics query \
  --workspace "$LAW_CUSTID" \
  --analytics-query "AzureDiagnostics | where Category == 'ApplicationGatewayFirewallLog' | where TimeGenerated > ago(24h) | take 1" \
  -o jsonc || true

echo ""
echo "== Recreate alert (delete if exists) =="
if az monitor scheduled-query show -g "$RG" -n "$ALERT_NAME" >/dev/null 2>&1; then
  az monitor scheduled-query delete -g "$RG" -n "$ALERT_NAME" -o none
  echo "ℹ️ Deleted existing: $ALERT_NAME"
fi

echo ""
echo "== Create alert: API WAF hits spike (> ${THRESHOLD} / 5m) =="
# We avoid action_s / ruleId_s entirely.
# This is a reliable proxy because ApplicationGatewayFirewallLog entries appear when WAF inspects/matches/blocks.
API_WAFHITS_KQL="AzureDiagnostics
| where TimeGenerated > ago(5m)
| where ResourceType == 'APPLICATIONGATEWAYS'
| where Category == 'ApplicationGatewayFirewallLog'
| where requestUri_s startswith '/api/'
| summarize hits=count() by _ResourceId
| where hits > ${THRESHOLD}"

az monitor scheduled-query create \
  -g "$RG" -n "$ALERT_NAME" \
  --scopes "$LAW_RESID" \
  --severity 2 \
  --evaluation-frequency "$FREQ" \
  --window-size "$WINDOW" \
  --condition \"count 'APIWAF' > 0 resource id _ResourceId at least 1 violations out of 1 aggregated points\" \
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
