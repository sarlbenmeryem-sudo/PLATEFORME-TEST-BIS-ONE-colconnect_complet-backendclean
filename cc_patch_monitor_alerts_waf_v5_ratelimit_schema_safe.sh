#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Fix RateLimit alert without ruleId_s (schema-safe)
# ID: CC_PATCH_MONITOR_ALERTS_WAF_V5_RATELIMIT_SCHEMA_SAFE_20260301
# ============================

RG="rg-colconnect-prod-frc"
LAW="law-colconnect-prod-frc"

echo "== [CC_PATCH_MONITOR_ALERTS_WAF_V5_RATELIMIT_SCHEMA_SAFE] Start =="

az account show -o none

LAW_ID="$(az monitor log-analytics workspace show -g "$RG" -n "$LAW" --query id -o tsv)"
if [[ -z "${LAW_ID:-}" ]]; then
  echo "❌ Cannot resolve LAW_ID"
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi

# We reuse your existing Action Group
AG_ID="$(az monitor action-group show -g "$RG" -n ag-colconnect-prod-alerts --query id -o tsv)"
if [[ -z "${AG_ID:-}" ]]; then
  echo "❌ Cannot resolve Action Group ID ag-colconnect-prod-alerts"
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi

echo "== Delete existing rate limit alert if present =="
if az monitor scheduled-query show -g "$RG" -n "alert-waf-ratelimit-spike" >/dev/null 2>&1; then
  az monitor scheduled-query delete -g "$RG" -n "alert-waf-ratelimit-spike" -o none
  echo "ℹ️ Deleted existing: alert-waf-ratelimit-spike"
fi

echo ""
echo "== Create RateLimit-proxy alert: blocked traffic spike on /api/ (>50/5m) =="

# Schema-safe query: no ruleId_s.
# We trigger when there are many WAF blocks on /api/ in a 5-minute window.
RATELIMIT_PROXY_KQL='AzureDiagnostics
| where TimeGenerated > ago(5m)
| where ResourceType == "APPLICATIONGATEWAYS"
| where Category == "ApplicationGatewayFirewallLog"
| where requestUri_s startswith "/api/"
| where action_s == "Block"
| summarize hits=count() by _ResourceId
| where hits > 50'

az monitor scheduled-query create \
  -g "$RG" -n "alert-waf-ratelimit-spike" \
  --scopes "$LAW_ID" \
  --severity 2 \
  --evaluation-frequency "PT5M" \
  --window-size "PT5M" \
  --condition "count 'APIBLOCKS' > 0 resource id _ResourceId at least 1 violations out of 1 aggregated points" \
  --condition-query APIBLOCKS="$RATELIMIT_PROXY_KQL" \
  --action-groups "$AG_ID" \
  -o none

echo "✅ Created: alert-waf-ratelimit-spike (proxy via /api/ blocks)"

echo ""
echo "== Verify scheduled-query rules =="
az monitor scheduled-query list -g "$RG" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
