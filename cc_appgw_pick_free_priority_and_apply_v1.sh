#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"
TARGET="./cc_appgw_enable_https_from_pfx_v1.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "❌ Target not found: $TARGET" >&2
  exit 1
fi
chmod +x "$TARGET" || true

echo "== Existing requestRoutingRules priorities =="
az network application-gateway rule list -g "$RG" --gateway-name "$APPGW" \
  --query "[].{name:name,priority:priority}" -o table

echo ""
echo "== Picking a free priority (start=100, step=10) =="
USED="$(az network application-gateway rule list -g "$RG" --gateway-name "$APPGW" \
  --query "[].priority" -o tsv | tr '\n' ' ')"

pick_free() {
  local p=100
  while true; do
    # check if p is in USED
    if echo " $USED " | grep -q " $p "; then
      p=$((p+10))
      continue
    fi
    echo "$p"
    return 0
  done
}

FREE="$(pick_free)"
echo "✅ Free priority found: $FREE"

echo ""
echo "== Re-run enable script with RULE_PRIORITY=$FREE =="
export RULE_PRIORITY="$FREE"
"$TARGET"

echo ""
echo "✅ Done"
echo "Rollback (git): git reset --hard HEAD~1"
