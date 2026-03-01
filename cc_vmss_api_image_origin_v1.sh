#!/usr/bin/env bash
set -euo pipefail

RG="rg-colconnect-prod-frc"
VMSS="vmss-api-colconnect-prod"

VM_ID="$(az vm list -g "$RG" --query "[?virtualMachineScaleSet.id!=null && contains(virtualMachineScaleSet.id, '$VMSS')].id | [0]" -o tsv)"
echo "VM_ID=$VM_ID"

az vm run-command invoke \
  --ids "$VM_ID" \
  --command-id RunShellScript \
  --scripts @- <<'SCRIPT'
bash -lc '
set -euo pipefail

echo "== docker ps (full) =="
docker ps --no-trunc || true
echo ""

CID="$(docker ps --format "{{.ID}}" | head -n 1 || true)"
echo "CID=$CID"
if [[ -z "${CID:-}" ]]; then
  echo "❌ no container"
  exit 0
fi

echo ""
echo "== docker inspect (image + cmd) =="
docker inspect "$CID" --format "Image={{.Config.Image}}\nCmd={{json .Config.Cmd}}\nEntrypoint={{json .Config.Entrypoint}}\nEnv={{json .Config.Env}}" || true

echo ""
echo "== systemd unit hints =="
systemctl list-units --type=service --all | grep -Ei "docker|container|colconnect|api|uvicorn|gunicorn" || true
'
SCRIPT

echo "Rollback (git): git reset --hard HEAD~1"
