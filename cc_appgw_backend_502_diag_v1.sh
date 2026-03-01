#!/usr/bin/env bash
set -euo pipefail
RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

echo "== Frontend public IP (AppGW) =="
FE_PIP_ID="$(az network application-gateway show -g "$RG" -n "$APPGW" --query "frontendIPConfigurations[0].publicIPAddress.id" -o tsv || true)"
echo "FE_PIP_ID=$FE_PIP_ID"
if [[ -n "${FE_PIP_ID:-}" ]]; then
  az network public-ip show --ids "$FE_PIP_ID" --query "{ip:ipAddress,fqdn:dnsSettings.fqdn,name:name}" -o jsonc
else
  echo "⚠️ No public IP attached to AppGW frontend"
fi

echo ""
echo "== Backend pools (addresses) =="
az network application-gateway address-pool list -g "$RG" --gateway-name "$APPGW" \
  --query "[].{name:name,backendAddresses:backendAddresses}" -o jsonc

echo ""
echo "== HTTP settings (ports/protocol/probe) =="
az network application-gateway http-settings list -g "$RG" --gateway-name "$APPGW" \
  --query "[].{name:name,port:port,protocol:protocol,probe:probe.id,hostName:hostName,pickHostNameFromBackendAddress:pickHostNameFromBackendAddress}" -o jsonc

echo ""
echo "== Probes (path/interval/host) =="
az network application-gateway probe list -g "$RG" --gateway-name "$APPGW" \
  --query "[].{name:name,protocol:protocol,path:path,interval:interval,timeout:timeout,unhealthyThreshold:unhealthyThreshold,host:host,pickHostNameFromBackendHttpSettings:pickHostNameFromBackendHttpSettings}" -o jsonc

echo ""
echo "== Backend health (why 502) =="
az network application-gateway show-backend-health -g "$RG" -n "$APPGW" -o jsonc

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
