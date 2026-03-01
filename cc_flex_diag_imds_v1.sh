#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
VMSS="vmss-api-colconnect-prod"
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
CID="970e04c8-ea16-47c3-8529-16a3a6b2a148"
IMDS="http://169.254.169.254/metadata/identity/oauth2/token"
RESOURCE="https://containerregistry.azure.net"
API="2018-02-01"

echo "== curl IMDS (with status code) =="
# print HTTP code on last line
RESP=$(curl -sS -D - -H "Metadata: true" "$IMDS?api-version=$API&resource=$RESOURCE&client_id=$CID" -o /tmp/imds_body.txt || true)
echo "$RESP" | sed -n "1,10p"
echo "--- body (first 300 chars) ---"
head -c 300 /tmp/imds_body.txt || true
echo
echo "--- end body ---"

echo "== show whether body looks like JSON =="
if head -c 1 /tmp/imds_body.txt | grep -q "{"; then
  echo "Looks like JSON"
else
  echo "NOT JSON"
fi
'
SCRIPT
done
