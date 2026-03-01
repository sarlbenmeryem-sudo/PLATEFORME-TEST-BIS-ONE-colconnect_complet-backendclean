#!/usr/bin/env bash
set -euo pipefail
RG="rg-colconnect-prod-frc"
NSG="nsg-api"
RULE="allow-appgw-subnet-to-api-8000"
SRC="10.10.0.0/24"
PORT="8000"

echo "== Check existing rule =="
if az network nsg rule show -g "$RG" --nsg-name "$NSG" -n "$RULE" >/dev/null 2>&1; then
  echo "✅ Rule already exists: $NSG/$RULE"
  exit 0
fi

echo "== Find free priority (120-199) =="
used="$(az network nsg rule list -g "$RG" --nsg-name "$NSG" --query "[].priority" -o tsv | tr '\n' ' ')"
prio=120
while echo " $used " | grep -q " $prio "; do
  prio=$((prio+1))
  if (( prio > 199 )); then
    echo "❌ No free priority in 120-199 for $NSG" >&2
    exit 1
  fi
done
echo "Using priority=$prio"

echo "== Create inbound allow: $SRC -> 8000 =="
az network nsg rule create \
  -g "$RG" --nsg-name "$NSG" -n "$RULE" \
  --priority "$prio" \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes "$SRC" \
  --source-port-ranges "*" \
  --destination-address-prefixes "*" \
  --destination-port-ranges "$PORT" \
  -o none

echo "✅ Added $RULE on $NSG"
echo "Rollback (git): git reset --hard HEAD~1"
