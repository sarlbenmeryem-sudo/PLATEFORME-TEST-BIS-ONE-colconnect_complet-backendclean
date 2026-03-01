#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Import PFX (colconnect.fr + www) -> KeyVault -> AppGW ssl-cert (robust)
# ID: CC_PATCH_APPGW_ADD_CERT_COLCONNECT_ROOT_WWW_V2_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"
KV="kv-colconnect-prod-frc"

CERT_NAME="cert-colconnect-root-www"
APPGW_SSL_CERT_NAME="ssl-colconnect-root-www"

: "${PFX_PATH:?Missing PFX_PATH. Example: export PFX_PATH='/mnt/c/Users/benme/Desktop/colconnect-root-www.pfx'}"
: "${PFX_PASS:?Missing PFX_PASS. Example: read -s -p 'PFX_PASS: ' PFX_PASS; echo; export PFX_PASS}"

echo "== [CC_PATCH_APPGW_ADD_CERT_COLCONNECT_ROOT_WWW_V2] Start =="
az account show -o none

echo "== Check PFX file =="
if [[ ! -f "$PFX_PATH" ]]; then
  echo "❌ PFX file not found: $PFX_PATH" >&2
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi
ls -lah "$PFX_PATH"

echo ""
echo "== Import certificate into Key Vault =="
# Import/update cert object in KV (idempotent)
az keyvault certificate import \
  --vault-name "$KV" \
  -n "$CERT_NAME" \
  -f "$PFX_PATH" \
  --password "$PFX_PASS" \
  -o none
echo "✅ KV certificate imported: $CERT_NAME"

echo ""
echo "== Resolve KV secret ID for the certificate =="
# AppGW needs secretId of the imported cert (KeyVault Secret)
SECRET_ID="$(az keyvault certificate show --vault-name "$KV" -n "$CERT_NAME" --query sid -o tsv)"
if [[ -z "${SECRET_ID:-}" ]]; then
  echo "❌ Cannot resolve KeyVault certificate secretId (sid) for $CERT_NAME" >&2
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi
echo "SECRET_ID=$SECRET_ID"

echo ""
echo "== Create/Update AppGW ssl-cert from Key Vault secret =="
# If exists -> update; else create
if az network application-gateway ssl-cert show -g "$RG" --gateway-name "$APPGW" -n "$APPGW_SSL_CERT_NAME" >/dev/null 2>&1; then
  az network application-gateway ssl-cert update \
    -g "$RG" --gateway-name "$APPGW" -n "$APPGW_SSL_CERT_NAME" \
    --key-vault-secret-id "$SECRET_ID" \
    -o none
  echo "✅ Updated AppGW ssl-cert: $APPGW_SSL_CERT_NAME"
else
  az network application-gateway ssl-cert create \
    -g "$RG" --gateway-name "$APPGW" -n "$APPGW_SSL_CERT_NAME" \
    --key-vault-secret-id "$SECRET_ID" \
    -o none
  echo "✅ Created AppGW ssl-cert: $APPGW_SSL_CERT_NAME"
fi

echo ""
echo "== Verify ssl-cert exists =="
az network application-gateway ssl-cert show \
  -g "$RG" --gateway-name "$APPGW" -n "$APPGW_SSL_CERT_NAME" \
  --query "{name:name,kvSecret:keyVaultSecretId,provisioningState:provisioningState}" -o jsonc

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
