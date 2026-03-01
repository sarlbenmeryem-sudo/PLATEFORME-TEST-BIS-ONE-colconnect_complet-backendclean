#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Create Storage Static Website (France Central) + upload vitrine
# ID: CC_PATCH_STORAGE_STATIC_CREATE_AND_UPLOAD_V1_20260301
# ============================

RG="rg-colconnect-prod-frc"
LOC="francecentral"

# Must be globally unique, lowercase, 3-24 chars
SA_NAME="stcolconnectfrprod$(date +%d%H%M)"   # creates a unique-ish suffix

VITRINE_DIR="./colconnect_vitrine"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing $1" >&2; exit 1; }; }
need az

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

if [[ ! -d "$VITRINE_DIR" ]]; then
  echo "❌ Missing $VITRINE_DIR. Generate vitrine first." >&2
  exit 1
fi

echo "== [1] Create Storage Account (France Central) =="
az_retry az storage account create \
  -g "$RG" -n "$SA_NAME" -l "$LOC" \
  --sku Standard_LRS --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  -o none
echo "✅ Storage created: $SA_NAME"

echo "== [2] Enable Static Website =="
az_retry az storage blob service-properties update \
  --account-name "$SA_NAME" \
  --static-website \
  --index-document index.html \
  --404-document index.html \
  -o none
echo "✅ Static website enabled"

echo "== [3] Upload files to \$web container =="
az_retry az storage blob upload-batch \
  --account-name "$SA_NAME" \
  -s "$VITRINE_DIR" \
  -d '$web' \
  --overwrite true \
  -o none
echo "✅ Upload done"

echo "== [4] Show endpoints =="
web_host="$(az storage account show -g "$RG" -n "$SA_NAME" --query "primaryEndpoints.web" -o tsv)"
blob_host="$(az storage account show -g "$RG" -n "$SA_NAME" --query "primaryEndpoints.blob" -o tsv)"
echo "WEB endpoint : $web_host"
echo "BLOB endpoint: $blob_host"

echo ""
echo "== Rollback Git (1 step) =="
echo "git reset --hard HEAD~1"
echo ""
echo "== Done =="
