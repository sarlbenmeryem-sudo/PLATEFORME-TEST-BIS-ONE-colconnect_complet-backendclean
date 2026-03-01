#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Storage Static Website (France Central) locked to AppGW subnet (EU-only)
# ID: CC_PATCH_FRONT_STORAGE_STATIC_EUONLY_V1_20260301
# ============================

RG="rg-colconnect-prod-frc"
LOC="francecentral"
VNET="vnet-colconnect-prod-frc"
APPGW_SUBNET="snet-appgw"

# Storage name must be globally unique, 3-24 lower+digits only
ST="stcolconnectfrontfrc01"

echo "== [CC_PATCH_FRONT_STORAGE_STATIC_EUONLY_V1] Start =="

az account show -o none

echo "== Ensure Storage Account exists =="
if az storage account show -g "$RG" -n "$ST" >/dev/null 2>&1; then
  echo "✅ Storage exists: $ST"
else
  az storage account create \
    -g "$RG" -n "$ST" -l "$LOC" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --min-tls-version TLS1_2 \
    --https-only true \
    --allow-blob-public-access false \
    -o none
  echo "✅ Created Storage: $ST"
fi

echo "== Enable Static Website =="
az storage blob service-properties update \
  --account-name "$ST" \
  --static-website \
  --index-document index.html \
  --404-document 404.html \
  -o none

echo "== Upload minimal vitrine files (idempotent) =="
TMPDIR="$(mktemp -d)"
cat > "$TMPDIR/index.html" <<'HTML'
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>ColConnect — Plateforme EU-only</title>
  <meta name="description" content="ColConnect — plateforme EU-only (France Central) pour les collectivités territoriales."/>
</head>
<body>
  <h1>ColConnect</h1>
  <p>Vitrine institutionnelle (EU-only — France Central).</p>
  <p><a href="https://api.colconnect.fr/api/docs">API Docs</a></p>
</body>
</html>
HTML

cat > "$TMPDIR/404.html" <<'HTML'
<!doctype html>
<html lang="fr">
<head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/><title>404</title></head>
<body><h1>404</h1><p>Page introuvable.</p></body>
</html>
HTML

# Use AAD auth (no account key)
az storage blob upload-batch \
  --account-name "$ST" \
  --auth-mode login \
  -s "$TMPDIR" \
  -d '$web' \
  --overwrite \
  -o none

echo "✅ Uploaded index.html + 404.html"

echo "== Ensure AppGW subnet has Microsoft.Storage service endpoint =="
az network vnet subnet update \
  -g "$RG" --vnet-name "$VNET" -n "$APPGW_SUBNET" \
  --service-endpoints Microsoft.Storage \
  -o none

echo "== Lock Storage network access: allow only AppGW subnet, deny by default =="
SUBNET_ID="$(az network vnet subnet show -g "$RG" --vnet-name "$VNET" -n "$APPGW_SUBNET" --query id -o tsv)"

# deny-by-default + allow selected subnet
az storage account update -g "$RG" -n "$ST" --default-action Deny -o none

# add vnet rule (idempotent)
if az storage account network-rule list -g "$RG" -n "$ST" --query "virtualNetworkRules[?virtualNetworkResourceId=='$SUBNET_ID'] | length(@)" -o tsv | grep -q '^1$'; then
  echo "✅ VNet rule already present"
else
  az storage account network-rule add -g "$RG" -n "$ST" --subnet "$SUBNET_ID" -o none
  echo "✅ Added VNet rule for AppGW subnet"
fi

echo "== Output static website hostnames =="
WEB_HOST="$(az storage account show -g "$RG" -n "$ST" --query "primaryEndpoints.web" -o tsv | sed 's#https\?://##' | sed 's#/$##')"
echo "WEB_HOST=$WEB_HOST"

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
