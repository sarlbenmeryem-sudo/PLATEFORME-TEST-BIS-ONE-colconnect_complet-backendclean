#!/usr/bin/env bash
set -euo pipefail
RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

echo "== AppGW Frontend IPs + Public IPs (if any) =="
az network application-gateway show -g "$RG" -n "$APPGW" --query "frontendIPConfigurations[].{name:name, private:privateIPAddress, public:publicIPAddress.id}" -o jsonc

echo ""
echo "== AppGW Frontend ports =="
az network application-gateway frontend-port list -g "$RG" --gateway-name "$APPGW" -o table

echo ""
echo "== List listeners =="
az network application-gateway http-listener list -g "$RG" --gateway-name "$APPGW" \
  --query "[].{name:name, host:hostName, fp:frontendPort.id, feip:frontendIpConfiguration.id, protocol:protocol}" -o table

echo ""
echo "== List request routing rules =="
az network application-gateway rule list -g "$RG" --gateway-name "$APPGW" \
  --query "[].{name:name, type:ruleType, listener:httpListener.id, backendPool:backendAddressPool.id, backendHttpSettings:backendHttpSettings.id, urlPathMap:urlPathMap.id, priority:priority}" -o table

echo ""
echo "== URL Path Maps =="
az network application-gateway url-path-map list -g "$RG" --gateway-name "$APPGW" -o jsonc | sed -n '1,260p'

echo ""
echo "== Backend pools =="
az network application-gateway address-pool list -g "$RG" --gateway-name "$APPGW" -o table

echo ""
echo "== Backend HTTP settings =="
az network application-gateway http-settings list -g "$RG" --gateway-name "$APPGW" -o jsonc | sed -n '1,260p'

echo ""
echo "== Probes =="
az network application-gateway probe list -g "$RG" --gateway-name "$APPGW" -o jsonc | sed -n '1,260p'

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
