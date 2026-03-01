#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
VMSS="vmss-api-colconnect-prod"
ACR_LOGIN="acrcolconnectprodfrc.azurecr.io"
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

ACR_LOGIN="acrcolconnectprodfrc.azurecr.io"
UAMI_CLIENT_ID="970e04c8-ea16-47c3-8529-16a3a6b2a148"

echo "== IMDS token test (UAMI) =="
IMDS="http://169.254.169.254/metadata/identity/oauth2/token"
RESOURCE="https://containerregistry.azure.net"
API="2018-02-01"

JSON=$(curl -fsS -H "Metadata: true" "$IMDS?api-version=$API&resource=$RESOURCE&client_id=$UAMI_CLIENT_ID")
TOKEN=$(python3 - <<PY
import json,sys
print(json.loads(sys.stdin.read())["access_token"])
PY
<<< "$JSON")

echo "== docker login ACR via AAD token =="
echo "$TOKEN" | docker login "$ACR_LOGIN" -u 00000000-0000-0000-0000-000000000000 --password-stdin
echo "✅ docker login OK"
'
SCRIPT
done

echo "== Done =="
