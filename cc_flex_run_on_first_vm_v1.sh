#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
VMSS="vmss-api-colconnect-prod"
ACR_LOGIN="acrcolconnectprodfrc.azurecr.io"
UAMI_CLIENT_ID="970e04c8-ea16-47c3-8529-16a3a6b2a148"

echo "== Resolve first VM resource ID for Flexible VMSS =="
VM_ID="$(az vm list -g "$RG" --query "[?virtualMachineScaleSet.id!=null && contains(virtualMachineScaleSet.id, '$VMSS')].id | [0]" -o tsv)"
if [[ -z "${VM_ID:-}" ]]; then
  echo "❌ No VM found for VMSS=$VMSS in RG=$RG" >&2
  echo "Tip: show VMs: az vm list -g $RG -o table" >&2
  exit 1
fi
echo "VM_ID=$VM_ID"

echo "== Run IMDS token + docker login on that VM =="
az vm run-command invoke \
  --ids "$VM_ID" \
  --command-id RunShellScript \
  --scripts @- <<SCRIPT
set -euo pipefail
echo "== IMDS token test (UAMI) =="
IMDS="http://169.254.169.254/metadata/identity/oauth2/token"
RESOURCE="https://containerregistry.azure.net"
API="2018-02-01"
CID="$UAMI_CLIENT_ID"

JSON=\$(curl -fsS -H "Metadata: true" "\$IMDS?api-version=\$API&resource=\$RESOURCE&client_id=\$CID")
TOKEN=\$(python3 - <<'PY'
import json,sys
print(json.loads(sys.stdin.read())["access_token"])
PY
<<< "\$JSON")

echo "== docker login ACR via AAD token =="
echo "\$TOKEN" | docker login "$ACR_LOGIN" -u 00000000-0000-0000-0000-000000000000 --password-stdin
echo "✅ docker login OK"
SCRIPT

echo "== Done =="
