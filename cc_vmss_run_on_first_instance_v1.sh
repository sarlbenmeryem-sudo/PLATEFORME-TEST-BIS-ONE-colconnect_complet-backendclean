#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
VMSS="vmss-api-colconnect-prod"
ACR_LOGIN="acrcolconnectprodfrc.azurecr.io"
UAMI_CLIENT_ID="970e04c8-ea16-47c3-8529-16a3a6b2a148"

echo "== Resolve first instance-id for $VMSS =="
IID="$(az vmss list-instances -g "$RG" -n "$VMSS" --query "[0].instanceId" -o tsv)"
if [[ -z "${IID:-}" ]]; then
  echo "❌ No instanceId found (is VMSS running?)" >&2
  exit 1
fi
echo "INSTANCE_ID=$IID"

echo "== Run IMDS token + docker login ACR on instance $IID =="
az vmss run-command invoke \
  -g "$RG" -n "$VMSS" \
  --instance-id "$IID" \
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
echo "\$TOKEN" | docker login "$ACR_LOGIN" \
  -u 00000000-0000-0000-0000-000000000000 \
  --password-stdin

echo "✅ docker login OK"
SCRIPT

echo "== Done =="
