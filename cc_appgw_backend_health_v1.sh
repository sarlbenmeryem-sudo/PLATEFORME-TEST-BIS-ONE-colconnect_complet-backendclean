#!/usr/bin/env bash
set -euo pipefail
RG="rg-colconnect-prod-frc"

echo "== App Gateways in RG =="
az network application-gateway list -g "$RG" --query "[].{name:name,id:id}" -o table

APPGW="$(az network application-gateway list -g "$RG" --query "[0].name" -o tsv)"
if [[ -z "${APPGW:-}" ]]; then
  echo "❌ No Application Gateway found in $RG" >&2
  exit 1
fi

echo ""
echo "== Using APPGW=$APPGW =="
az network application-gateway show-backend-health -g "$RG" -n "$APPGW" -o jsonc | sed -n '1,260p'

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
