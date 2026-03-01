#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
VMSS="vmss-api-colconnect-prod"
ACR_LOGIN="acrcolconnectprodfrc.azurecr.io"
IMG="acrcolconnectprodfrc.azurecr.io/colconnect-api:prod"
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
IMG="acrcolconnectprodfrc.azurecr.io/colconnect-api:prod"
CID="970e04c8-ea16-47c3-8529-16a3a6b2a148"
IMDS="http://169.254.169.254/metadata/identity/oauth2/token"
RESOURCE="https://containerregistry.azure.net"
API="2018-02-01"

BODY=$(curl -fsS -H "Metadata: true" "$IMDS?api-version=$API&resource=$RESOURCE&client_id=$CID")
TOKEN=$(printf "%s" "$BODY" | sed -n "s/.*\"access_token\":\"\\([^\"]*\\)\".*/\\1/p")

if [ -z "$TOKEN" ]; then
  echo "❌ Could not extract access_token" >&2
  exit 1
fi

echo "$TOKEN" | docker login "$ACR_LOGIN" -u 00000000-0000-0000-0000-000000000000 --password-stdin

docker pull "$IMG"

docker rm -f colconnect-api >/dev/null 2>&1 || true
docker run -d --name colconnect-api --restart=always \
  -p 8000:8000 \
  -e PORT=8000 \
  -e APP_MODULE="main:app" \
  "$IMG"

echo "== health local =="
curl -fsS http://127.0.0.1:8000/health && echo

echo "== docker ps =="
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}"

echo "== last logs (if any) =="
docker logs --tail=60 colconnect-api || true
'
SCRIPT
done

echo "== Done =="
