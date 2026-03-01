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
CID="$(docker ps --format "{{.ID}}\t{{.Names}}" | awk '\''$2=="colconnect-api"{print $1; exit}'\'' || true)"
if [[ -z "${CID:-}" ]]; then
  CID="$(docker ps --format "{{.ID}}" | head -n 1 || true)"
fi
echo "CID=$CID"
if [[ -z "${CID:-}" ]]; then exit 0; fi

echo "== ENV (sorted) =="
docker inspect "$CID" --format "{{range .Config.Env}}{{println .}}{{end}}" | sort
'
SCRIPT

echo "Rollback (git): git reset --hard HEAD~1"
