#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Import correct PFX (colconnect.fr + www) -> KeyVault -> AppGW ssl-cert
# ID: CC_PATCH_APPGW_ADD_CERT_COLCONNECT_FR_AUTODETECT_PFX_V4_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"
KV="kv-colconnect-prod-frc"

CERT_NAME="cert-colconnect-fr"
APPGW_SSL_CERT_NAME="ssl-colconnect-fr"

PFX_PASS="${PFX_PASS:-}"
PFX_PATH="${PFX_PATH:-}"   # optional override

need(){ command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing $1" >&2; exit 1; }; }
need az
need find
need openssl

if [[ -z "${PFX_PASS:-}" ]]; then
  echo "❌ PFX_PASS env var required."
  echo "   Example: export PFX_PASS='your_real_pfx_password'"
  exit 1
fi

az account show -o none

az_retry() {
  local max=14 n=1 delay=8
  while true; do
    set +e
    out="$("$@" 2>&1)"; code=$?
    set -e
    if [[ $code -eq 0 ]]; then return 0; fi
    if echo "$out" | grep -Eqi "PutApplicationGatewayOperation|Another operation is in progress|OperationPreempted|was being modified|TooManyRequests|429|timeout|temporar|Transient"; then
      if [[ $n -ge $max ]]; then
        echo "❌ Retry exhausted ($max). Last error:" >&2
        echo "$out" >&2
        return 1
      fi
      echo "⏳ Transient/AppGW busy (retry $n/$max) in ${delay}s..."
      sleep "$delay"; n=$((n+1)); delay=$((delay+6))
      continue
    fi
    echo "❌ Azure command failed:" >&2
    echo "$out" >&2
    return 1
  done
}

echo "== [1] Select PFX =="

if [[ -n "${PFX_PATH:-}" ]]; then
  if [[ ! -f "$PFX_PATH" ]]; then
    echo "❌ PFX_PATH provided but file not found: $PFX_PATH" >&2
    exit 1
  fi
  echo "✅ Using forced PFX_PATH: $PFX_PATH"
else
  echo "Scanning for .pfx under ., .., ./certs, ./secrets (maxdepth 4)..."
  all="$(find . .. ./certs ./secrets -maxdepth 4 -type f -iname '*.pfx' 2>/dev/null || true)"
  if [[ -z "${all:-}" ]]; then
    echo "❌ No .pfx found." >&2
    exit 1
  fi

  echo "== Candidates (raw) =="
  echo "$all" | nl -ba

  # Prefer pfx containing "colconnect" but NOT containing "api"
  picked="$(echo "$all" | grep -i 'colconnect' | grep -iv 'api' | head -n 1 || true)"
  if [[ -z "${picked:-}" ]]; then
    # fallback: any pfx with "colconnect"
    picked="$(echo "$all" | grep -i 'colconnect' | head -n 1 || true)"
  fi

  if [[ -z "${picked:-}" ]]; then
    echo "❌ Could not autodetect a PFX for colconnect.fr (none matched 'colconnect')." >&2
    echo "   Fix: export PFX_PATH=/path/to/colconnect_fr.pfx" >&2
    exit 1
  fi

  PFX_PATH="$picked"
  echo "✅ Selected PFX: $PFX_PATH"
fi

echo ""
echo "== [2] Validate PKCS#12 locally (password check) =="
set +e
openssl_out="$(openssl pkcs12 -in "$PFX_PATH" -info -noout -passin "pass:${PFX_PASS}" 2>&1)"
code=$?
set -e
if [[ $code -ne 0 ]]; then
  echo "❌ PFX validation failed. Common causes:" >&2
  echo "   - wrong PFX_PASS" >&2
  echo "   - file is not valid PKCS#12" >&2
  echo "OpenSSL says:" >&2
  echo "$openssl_out" >&2
  exit 1
fi
echo "✅ PFX is readable with provided password"

echo ""
echo "== [3] Import certificate into KeyVault =="
az_retry az keyvault certificate import \
  --vault-name "$KV" \
  -n "$CERT_NAME" \
  -f "$PFX_PATH" \
  --password "$PFX_PASS" \
  -o none
echo "✅ Imported to KV: $CERT_NAME"

secret_id="$(az keyvault certificate show --vault-name "$KV" -n "$CERT_NAME" --query "sid" -o tsv)"
if [[ -z "${secret_id:-}" ]]; then
  echo "❌ Could not get secret id (sid) from KeyVault certificate" >&2
  exit 1
fi
echo "KV secret id: $secret_id"

echo ""
echo "== [4] Attach certificate to AppGW ssl-cert =="
if az network application-gateway ssl-cert show -g "$RG" --gateway-name "$APPGW" -n "$APPGW_SSL_CERT_NAME" >/dev/null 2>&1; then
  az_retry az network application-gateway ssl-cert update -g "$RG" --gateway-name "$APPGW" -n "$APPGW_SSL_CERT_NAME" \
    --key-vault-secret-id "$secret_id" -o none
  echo "✅ Updated AppGW ssl-cert: $APPGW_SSL_CERT_NAME"
else
  az_retry az network application-gateway ssl-cert create -g "$RG" --gateway-name "$APPGW" -n "$APPGW_SSL_CERT_NAME" \
    --key-vault-secret-id "$secret_id" -o none
  echo "✅ Created AppGW ssl-cert: $APPGW_SSL_CERT_NAME"
fi

echo ""
echo "== [5] Confirm ssl-cert exists =="
az network application-gateway ssl-cert show -g "$RG" --gateway-name "$APPGW" -n "$APPGW_SSL_CERT_NAME" --query "{name:name,keyVaultSecretId:keyVaultSecretId}" -o table

echo ""
echo "== Rollback Git (1 step) =="
echo "git reset --hard HEAD~1"
echo "== Done =="
