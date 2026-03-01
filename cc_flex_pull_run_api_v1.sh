#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
VMSS="vmss-api-colconnect-prod"
ACR_LOGIN="acrcolconnectprodfrc.azurecr.io"
IMG="acrcolconnectprodfrc.azurecr.io/colconnect-api:prod"
UAMI_CLIENT_ID="970e04c8-ea16-47c3-8529-16a3a6b2a148"

VM_ID="$(az vm list -g "$RG" --query "[?virtualMachineScaleSet.id!=null && contains(virtualMachineScaleSet.id, '$VMSS')].id | [0]" -o tsv)"
if [[ -z "${VM_ID:-}" ]]; then
  echo "❌ No VM found for VMSS=$VMSS in RG=$RG" >&2
  exit 1
fi
echo "VM_ID=$VM_ID"

az vm run-command invoke \
  --ids "$VM_ID" \
  --command-id RunShellScript \
  --scripts @- <<SCRIPT
set -euo pipefail
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

echo "\$TOKEN" | docker login "$ACR_LOGIN" -u 00000000-0000-0000-0000-000000000000 --password-stdin

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
SCRIPT

echo "== Done =="
