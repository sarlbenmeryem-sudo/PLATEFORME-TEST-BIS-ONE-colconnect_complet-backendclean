#!/usr/bin/env bash
set -euo pipefail
RG="rg-colconnect-prod-frc"
PIP="pip-appgw-colconnect-prod"

echo "== Public IP (PIP) =="
az network public-ip show -g "$RG" -n "$PIP" --query "{name:name, ip:ipAddress, fqdn:dnsSettings.fqdn, sku:sku.name, allocation:publicIPAllocationMethod}" -o jsonc

IP="$(az network public-ip show -g "$RG" -n "$PIP" --query "ipAddress" -o tsv)"
FQDN="$(az network public-ip show -g "$RG" -n "$PIP" --query "dnsSettings.fqdn" -o tsv)"

echo ""
echo "== Quick tests (HTTP 80) =="
if [[ -n "${FQDN:-}" ]]; then
  echo "-- FQDN: $FQDN --"
  curl -sv --max-time 8 "http://$FQDN/" || true
  curl -sv --max-time 8 "http://$FQDN/api/health" || true
  curl -sv --max-time 8 "http://$FQDN/api/docs" || true
  curl -sv --max-time 8 "http://$FQDN/api/openapi.json" || true
fi

if [[ -n "${IP:-}" ]]; then
  echo "-- IP: $IP --"
  curl -sv --max-time 8 "http://$IP/" || true
  curl -sv --max-time 8 "http://$IP/api/health" || true
  curl -sv --max-time 8 "http://$IP/api/docs" || true
  curl -sv --max-time 8 "http://$IP/api/openapi.json" || true
fi

echo ""
echo "NOTE: tu n'as PAS de listener 443 (HTTPS) sur l'AppGW, donc tests en http:// uniquement."
echo "Rollback (git): git reset --hard HEAD~1"
