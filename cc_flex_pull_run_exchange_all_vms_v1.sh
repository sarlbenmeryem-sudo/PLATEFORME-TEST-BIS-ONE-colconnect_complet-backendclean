#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
VMSS="vmss-api-colconnect-prod"
IMG="acrcolconnectprodfrc.azurecr.io/colconnect-api:prod"
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
IMG="acrcolconnectprodfrc.azurecr.io/colconnect-api:prod"
TENANT="b0b26265-281b-4f00-9d42-0eea7dcf336d"
CID="970e04c8-ea16-47c3-8529-16a3a6b2a148"

IMDS="http://169.254.169.254/metadata/identity/oauth2/token"
API="2018-02-01"
RESOURCE_ARM="https://management.azure.com/"

BODY=$(curl -fsS -H "Metadata: true" "$IMDS?api-version=$API&resource=$RESOURCE_ARM&client_id=$CID")
AAD=$(printf "%s" "$BODY" | sed -n "s/.*\"access_token\":\"\\([^\"]*\\)\".*/\\1/p")
[ -n "$AAD" ] || { echo "❌ No ARM token"; exit 1; }

EXCH=$(curl -fsS -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=access_token" \
  --data-urlencode "service=$ACR" \
  --data-urlencode "tenant=$TENANT" \
  --data-urlencode "access_token=$AAD" \
  "https://$ACR/oauth2/exchange")

REFRESH=$(printf "%s" "$EXCH" | sed -n "s/.*\"refresh_token\":\"\\([^\"]*\\)\".*/\\1/p")
[ -n "$REFRESH" ] || { echo "❌ No refresh_token"; echo "$EXCH" | head -c 200; echo; exit 1; }

echo "$REFRESH" | docker login "$ACR" -u 00000000-0000-0000-0000-000000000000 --password-stdin

docker pull "$IMG"

docker rm -f colconnect-api >/dev/null 2>&1 || true
docker run -d --name colconnect-api --restart=always \
  -p 8000:8000 \
  -e PORT=8000 \
  -e APP_MODULE="main:app" \
  "$IMG"

echo "== health local =="
curl -fsS http://127.0.0.1:8000/health && echo

docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}"
docker logs --tail=50 colconnect-api || true
'
SCRIPT
done

echo "== Done =="
