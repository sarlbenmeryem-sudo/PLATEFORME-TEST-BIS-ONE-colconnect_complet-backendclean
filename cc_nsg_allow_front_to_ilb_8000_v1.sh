#!/usr/bin/env bash
set -euo pipefail
RG="rg-colconnect-prod-frc"

# 👉 Mets ici le NSG FRONT quand on l'aura identifié (ex: nsg-front)
NSG_FRONT="${1:-}"

ILB_IP="10.10.2.10"
PORT="8000"
RULE="allow-front-to-ilb-8000"

if [[ -z "$NSG_FRONT" ]]; then
  echo "Usage: $0 <NSG_FRONT_NAME>" >&2
  exit 2
fi

echo "== Check if rule exists =="
if az network nsg rule show -g "$RG" --nsg-name "$NSG_FRONT" -n "$RULE" >/dev/null 2>&1; then
  echo "✅ Rule already exists: $RULE"
  exit 0
fi

echo "== Find free priority (200-400) =="
used="$(az network nsg rule list -g "$RG" --nsg-name "$NSG_FRONT" --query "[].priority" -o tsv | tr '\n' ' ')"
prio=200
while echo " $used " | grep -q " $prio "; do
  prio=$((prio+1))
  if (( prio > 400 )); then
    echo "❌ No free priority in 200-400" >&2
    exit 1
  fi
done
echo "Using priority=$prio"

echo "== Create rule: allow VNet(front) -> ILB:8000 =="
az network nsg rule create \
  -g "$RG" --nsg-name "$NSG_FRONT" -n "$RULE" \
  --priority "$prio" \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes VirtualNetwork \
  --source-port-ranges "*" \
  --destination-address-prefixes "${ILB_IP}/32" \
  --destination-port-ranges "$PORT" \
  -o none

echo "✅ Added $RULE on $NSG_FRONT"
echo "Rollback (git): git reset --hard HEAD~1"
