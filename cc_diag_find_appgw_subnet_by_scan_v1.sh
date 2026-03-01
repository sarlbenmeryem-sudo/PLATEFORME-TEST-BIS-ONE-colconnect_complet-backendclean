#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing $1" >&2; exit 1; }; }
need az
need jq

az account show -o none

echo "== [DIAG] Scan VNets/subnets in RG to locate AppGW subnet =="

vnets="$(az network vnet list -g "$RG" -o json)"
count="$(echo "$vnets" | jq 'length')"
if [[ "$count" -eq 0 ]]; then
  echo "❌ No VNets found in RG=$RG" >&2
  exit 1
fi

found=""

for vnet in $(echo "$vnets" | jq -r '.[].name'); do
  echo ""
  echo "-- VNet: $vnet --"
  subnets="$(az network vnet subnet list -g "$RG" --vnet-name "$vnet" -o json)"

  # Heuristic: subnet object contains references to applicationGateways somewhere
  # We search in: ipConfigurations, serviceAssociationLinks, resourceNavigationLinks, delegations (as string)
  match="$(echo "$subnets" | jq -r --arg APPGW "$APPGW" '
    .[] | select(
      (tostring | test("/applicationGateways/" + $APPGW)) or
      (tostring | test("applicationGateways/" + $APPGW))
    ) | @base64
  ' | head -n 1 || true)"

  if [[ -n "${match:-}" ]]; then
    obj="$(echo "$match" | base64 -d)"
    name="$(echo "$obj" | jq -r '.name')"
    id="$(echo "$obj" | jq -r '.id')"
    prefixes="$(echo "$obj" | jq -c '.addressPrefixes // [.addressPrefix]')"

    echo "✅ FOUND AppGW subnet:"
    echo "VNet   : $vnet"
    echo "Subnet : $name"
    echo "ID     : $id"
    echo "CIDR   : $prefixes"
    found="yes"
    break
  else
    echo "No match in this VNet."
  fi
done

if [[ -z "${found:-}" ]]; then
  echo ""
  echo "❌ Could not locate AppGW subnet by scan."
  echo "   Most likely RBAC issue: you can read AppGW but not enough of VNet/Subnet linkage."
  echo ""
  echo "Quick RBAC hint (non-destructive):"
  echo "  az network vnet list -g $RG -o table"
  echo "  az role assignment list --assignee \$(az ad signed-in-user show --query id -o tsv) --scope \$(az group show -n $RG --query id -o tsv) -o table"
  exit 2
fi
