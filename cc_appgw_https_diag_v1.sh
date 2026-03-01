#!/usr/bin/env bash
set -euo pipefail
RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

echo "== Frontend ports =="
az network application-gateway frontend-port list -g "$RG" --gateway-name "$APPGW" -o table

echo ""
echo "== Listeners (name/protocol/port) =="
az network application-gateway http-listener list -g "$RG" --gateway-name "$APPGW" \
  --query "[].{name:name,protocol:protocol,port:frontendPort.id,host:hostName}" -o table

echo ""
echo "== SSL certs attached to AppGW =="
az network application-gateway ssl-cert list -g "$RG" --gateway-name "$APPGW" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
