#!/usr/bin/env bash
set -euo pipefail
RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

echo "== Frontend ports =="
az network application-gateway frontend-port list -g "$RG" --gateway-name "$APPGW" -o table

echo ""
echo "== List listeners (protocol/port) =="
az network application-gateway http-listener list -g "$RG" --gateway-name "$APPGW" \
  --query "[].{name:name,protocol:protocol,host:hostName,frontendPort:frontendPort.id}" -o table

echo ""
echo "== SSL certs =="
az network application-gateway ssl-cert list -g "$RG" --gateway-name "$APPGW" -o table

echo ""
echo "== Rules =="
az network application-gateway rule list -g "$RG" --gateway-name "$APPGW" \
  --query "[].{name:name,priority:priority,type:ruleType,listener:httpListener.id,redirect:redirectConfiguration.id,urlPathMap:urlPathMap.id}" -o table

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
