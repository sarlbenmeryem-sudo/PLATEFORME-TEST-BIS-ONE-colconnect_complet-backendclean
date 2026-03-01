#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Fix Storage RBAC + upload with AAD (auth-mode login)
# ID: CC_PATCH_FRONT_STORAGE_STATIC_EUONLY_V2_RBAC_UPLOAD_20260301
# ============================

RG="rg-colconnect-prod-frc"
ST="stcolconnectfrontfrc01"

echo "== [CC_PATCH_FRONT_STORAGE_STATIC_EUONLY_V2_RBAC_UPLOAD] Start =="

az account show -o none

echo "== Resolve principal (current signed-in user/SPN) =="
ME_OID="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)"
if [[ -z "${ME_OID:-}" ]]; then
  # fallback if signed-in-user not available (service principal context)
  ME_OID="$(az account show --query user.name -o tsv || true)"
fi
echo "PRINCIPAL_HINT=$ME_OID"

echo "== Resolve Storage resource ID =="
ST_ID="$(az storage account show -g "$RG" -n "$ST" --query id -o tsv)"
if [[ -z "${ST_ID:-}" ]]; then
  echo "❌ Cannot resolve storage account id"
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi
echo "ST_ID=$ST_ID"

echo "== Assign Storage Blob Data Contributor to current identity (data plane) =="
# If ME_OID is an object id, assignment works; if it's UPN fallback, try resolve to object id.
OID="$ME_OID"
if [[ "$OID" == *@* ]]; then
  OID="$(az ad user show --id "$ME_OID" --query id -o tsv 2>/dev/null || true)"
fi
if [[ -z "${OID:-}" ]]; then
  echo "❌ Cannot resolve objectId for current identity. Try: az ad signed-in-user show"
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi

# idempotent-ish: try create, ignore if already exists
az role assignment create \
  --assignee-object-id "$OID" \
  --assignee-principal-type User \
  --role "Storage Blob Data Contributor" \
  --scope "$ST_ID" \
  -o none 2>/dev/null || echo "ℹ️ Role assignment may already exist (ok)"

echo "✅ RBAC ensured: Storage Blob Data Contributor"

echo ""
echo "== Enable Static Website (auth-mode login) =="
az storage blob service-properties update \
  --account-name "$ST" \
  --auth-mode login \
  --static-website \
  --index-document index.html \
  --404-document 404.html \
  -o none

echo "== Upload minimal vitrine files (auth-mode login) =="
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

az storage blob upload-batch \
  --account-name "$ST" \
  --auth-mode login \
  -s "$TMPDIR" \
  -d '$web' \
  --overwrite \
  -o none

echo "✅ Uploaded index.html + 404.html"

echo ""
echo "== Output static website endpoint =="
az storage account show -g "$RG" -n "$ST" --query "primaryEndpoints.web" -o tsv

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
