#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
VMSS="vmss-api-colconnect-prod"
ACR_LOGIN="acrcolconnectprodfrc.azurecr.io"
TENANT_ID="b0b26265-281b-4f00-9d42-0eea7dcf336d"
UAMI_CLIENT_ID="970e04c8-ea16-47c3-8529-16a3a6b2a148"

mapfile -t VM_IDS < <(az vm list -g "$RG" --query "[?virtualMachineScaleSet.id!=null && contains(virtualMachineScaleSet.id, '$VMSS')].id" -o tsv)
if (( ${#VM_IDS[@]} == 0 )); then
  echo "❌ No VMs found for VMSS=$VMSS" >&2
  exit 1
fi

for VM_ID in "${VM_IDS[@]}"; do
  echo "== VM: $VM_ID =="
  az vm run-command invoke \
    --ids "$VM_ID" \
    --command-id RunShellScript \
    --scripts @- <<'SCRIPT'
bash -lc '
set -euo pipefail

ACR="acrcolconnectprodfrc.azurecr.io"
TENANT="b0b26265-281b-4f00-9d42-0eea7dcf336d"
CID="970e04c8-ea16-47c3-8529-16a3a6b2a148"

IMDS="http://169.254.169.254/metadata/identity/oauth2/token"
API="2018-02-01"
RESOURCE_ARM="https://management.azure.com/"

echo "== 1) Get AAD access token (audience ARM) via IMDS =="
BODY=$(curl -fsS -H "Metadata: true" "$IMDS?api-version=$API&resource=$RESOURCE_ARM&client_id=$CID")
AAD=$(printf "%s" "$BODY" | sed -n "s/.*\"access_token\":\"\\([^\"]*\\)\".*/\\1/p")
if [ -z "$AAD" ]; then
  echo "❌ Cannot extract AAD access_token for ARM. Body head:"
  echo "$BODY" | head -c 200; echo
  exit 1
fi

echo "== 2) Exchange AAD token for ACR refresh token =="
EXCH=$(curl -fsS -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=access_token" \
  --data-urlencode "service=$ACR" \
  --data-urlencode "tenant=$TENANT" \
  --data-urlencode "access_token=$AAD" \
  "https://$ACR/oauth2/exchange")

REFRESH=$(printf "%s" "$EXCH" | sed -n "s/.*\"refresh_token\":\"\\([^\"]*\\)\".*/\\1/p")
if [ -z "$REFRESH" ]; then
  echo "❌ Cannot extract refresh_token. Exchange response head:"
  echo "$EXCH" | head -c 200; echo
  exit 1
fi

echo "== 3) docker login with ACR refresh token =="
echo "$REFRESH" | docker login "$ACR" -u 00000000-0000-0000-0000-000000000000 --password-stdin

echo "✅ docker login OK (refresh token)"
'
SCRIPT
done

echo "== Done =="
