#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Autodetect PFX (colconnect.fr + www) on Desktop -> KeyVault -> AppGW ssl-cert
# ID: CC_PATCH_APPGW_ADD_CERT_COLCONNECT_ROOT_WWW_AUTODETECT_V3_20260301
# ============================

RG="rg-colconnect-prod-frc"
APPGW="agw-colconnect-prod"
KV="kv-colconnect-prod-frc"

CERT_NAME="cert-colconnect-root-www"
APPGW_SSL_CERT_NAME="ssl-colconnect-root-www"

DESK="/mnt/c/Users/benme/Desktop"

: "${PFX_PASS:?Missing PFX_PASS. Example: read -s -p 'PFX_PASS: ' PFX_PASS; echo; export PFX_PASS}"

echo "== [CC_PATCH_APPGW_ADD_CERT_COLCONNECT_ROOT_WWW_AUTODETECT_V3] Start =="
az account show -o none

echo "== Search PFX candidates on Desktop =="
mapfile -t CANDS < <(find "$DESK" -maxdepth 3 -type f \( -iname "*.pfx" -o -iname "*.p12" \) 2>/dev/null | sort)

if [[ "${#CANDS[@]}" -eq 0 ]]; then
  echo "❌ No PFX/P12 files found under: $DESK"
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi

echo "Found:"
printf ' - %s\n' "${CANDS[@]}" | head -n 50

echo ""
echo "== Pick best match (prefer filenames containing root/www/colconnect, exclude api-colconnect if possible) =="

BEST=""
for f in "${CANDS[@]}"; do
  bn="$(basename "$f" | tr '[:upper:]' '[:lower:]')"
  if [[ "$bn" == *"colconnect"* && ( "$bn" == *"root"* || "$bn" == *"www"* || "$bn" == *"wild"* ) ]]; then
    BEST="$f"
    break
  fi
done

# fallback: any pfx containing colconnect but not api
if [[ -z "$BEST" ]]; then
  for f in "${CANDS[@]}"; do
    bn="$(basename "$f" | tr '[:upper:]' '[:lower:]')"
    if [[ "$bn" == *"colconnect"* && "$bn" != *"api"* ]]; then
      BEST="$f"
      break
    fi
  done
fi

if [[ -z "$BEST" ]]; then
  echo "❌ Could not autodetect a root/www PFX. Create it and put it on Desktop, then rerun."
  echo "Hint: expected names like: colconnect-root-www.pfx or colconnect_fullchain.pfx"
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi

export PFX_PATH="$BEST"
echo "✅ Using PFX_PATH=$PFX_PATH"
ls -lah "$PFX_PATH"

echo ""
echo "== Import certificate into Key Vault =="
az keyvault certificate import \
  --vault-name "$KV" \
  -n "$CERT_NAME" \
  -f "$PFX_PATH" \
  --password "$PFX_PASS" \
  -o none
echo "✅ KV certificate imported: $CERT_NAME"

echo ""
echo "== Resolve KV secret ID (sid) =="
SECRET_ID="$(az keyvault certificate show --vault-name "$KV" -n "$CERT_NAME" --query sid -o tsv)"
if [[ -z "${SECRET_ID:-}" ]]; then
  echo "❌ Cannot resolve secretId for $CERT_NAME"
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi
echo "SECRET_ID=$SECRET_ID"

echo ""
echo "== Create/Update AppGW ssl-cert =="
if az network application-gateway ssl-cert show -g "$RG" --gateway-name "$APPGW" -n "$APPGW_SSL_CERT_NAME" >/dev/null 2>&1; then
  az network application-gateway ssl-cert update \
    -g "$RG" --gateway-name "$APPGW" -n "$APPGW_SSL_CERT_NAME" \
    --key-vault-secret-id "$SECRET_ID" \
    -o none
  echo "✅ Updated ssl-cert: $APPGW_SSL_CERT_NAME"
else
  az network application-gateway ssl-cert create \
    -g "$RG" --gateway-name "$APPGW" -n "$APPGW_SSL_CERT_NAME" \
    --key-vault-secret-id "$SECRET_ID" \
    -o none
  echo "✅ Created ssl-cert: $APPGW_SSL_CERT_NAME"
fi

echo ""
echo "== Verify ssl-cert exists =="
az network application-gateway ssl-cert show \
  -g "$RG" --gateway-name "$APPGW" -n "$APPGW_SSL_CERT_NAME" \
  --query "{name:name,kvSecret:keyVaultSecretId,provisioningState:provisioningState}" -o jsonc

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
