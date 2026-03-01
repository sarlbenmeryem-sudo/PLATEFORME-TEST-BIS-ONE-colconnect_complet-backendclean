#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Create SWA (management France Central) for colconnect.fr
# ID: CC_PATCH_SWA_CREATE_COLCONNECT_FR_V2_20260301
# ============================

RG="rg-colconnect-prod-frc"
LOC="francecentral"
SWA_NAME="swa-colconnect-fr-prod"
SKU="Standard"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing $1" >&2; exit 1; }; }
need az
need jq

az account show -o none

az_retry() {
  local max=10 n=1 delay=6
  while true; do
    set +e
    out="$("$@" 2>&1)"; code=$?
    set -e
    if [[ $code -eq 0 ]]; then return 0; fi
    if echo "$out" | grep -Eqi "TooManyRequests|429|timeout|temporar|Transient|Conflict|Another operation"; then
      if [[ $n -ge $max ]]; then
        echo "❌ Retry exhausted ($max). Last error:" >&2
        echo "$out" >&2
        return 1
      fi
      echo "⏳ Azure transient error (retry $n/$max) in ${delay}s..."
      sleep "$delay"; n=$((n+1)); delay=$((delay+4))
      continue
    fi
    echo "❌ Azure command failed:" >&2
    echo "$out" >&2
    return 1
  done
}

az group show -n "$RG" -o none

az extension add --name staticwebapp >/dev/null 2>&1 || az extension update --name staticwebapp -o none

if az staticwebapp show -n "$SWA_NAME" -g "$RG" >/dev/null 2>&1; then
  echo "✅ SWA exists: $SWA_NAME"
else
  echo "Creating SWA: $SWA_NAME"
  az_retry az staticwebapp create -n "$SWA_NAME" -g "$RG" -l "$LOC" --sku "$SKU" -o none
  echo "✅ SWA created"
fi

default_host="$(az staticwebapp show -n "$SWA_NAME" -g "$RG" --query "defaultHostname" -o tsv)"
echo "defaultHostname: $default_host"

echo "== Rollback Git (1 step) =="
echo "git reset --hard HEAD~1"
echo "== Done =="
