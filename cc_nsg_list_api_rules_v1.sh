#!/usr/bin/env bash
set -euo pipefail
RG="rg-colconnect-prod-frc"
NSG="nsg-api"

az network nsg rule list -g "$RG" --nsg-name "$NSG" \
  --query "[].{name:name,prio:priority,dir:direction,access:access,proto:protocol,src:sourceAddressPrefix,dstPort:destinationPortRange}" \
  -o table
