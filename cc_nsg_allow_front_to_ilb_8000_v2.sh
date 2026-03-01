#!/usr/bin/env bash
set -euo pipefail
RG="rg-colconnect-prod-frc"

NSG_NAME="${1:-}"
ILB_IP="10.10.2.10"
PORT="8000"
RULE="allow-front-to-ilb-8000"

if [[ -z "$NSG_NAME" ]]; then
  echo "Usage: $0 <NSG_NAME>" >&2
  exit 2
fi

echo "== Check existing rule =="
if az network nsg rule show -g "$RG" --nsg-name "$NSG_NAME" -n "$RULE" >/dev/null 2>&1; then
  echo "✅ Rule already exists on $NSG_NAME: $RULE"
  exit 0
fi

echo "== Find free priority (220-399) =="
used="$(az network nsg rule list -g "$RG" --nsg-name "$NSG_NAME" --query "[].priority" -o tsv | tr '\n' ' ')"
prio=220
while echo " $used " | grep -q " $prio "; do
  prio=$((prio+1))
  if (( prio > 399 )); then
    echo "❌ No free priority in 220-399 for $NSG_NAME" >&2
    exit 1
  fi
done
echo "Using priority=$prio"

echo "== Create outbound allow: FRONT -> ILB:8000 =="
az network nsg rule create \
  -g "$RG" --nsg-name "$NSG_NAME" -n "$RULE" \
  --priority "$prio" \
  --direction Outbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes VirtualNetwork \
  --source-port-ranges "*" \
  --destination-address-prefixes "${ILB_IP}/32" \
  --destination-port-ranges "$PORT" \
  -o none

echo "✅ Added outbound rule $RULE on $NSG_NAME"
echo "Rollback (git): git reset --hard HEAD~1"
