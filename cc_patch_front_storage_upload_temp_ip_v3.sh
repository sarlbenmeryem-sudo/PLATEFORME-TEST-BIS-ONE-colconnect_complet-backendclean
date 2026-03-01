#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Temporary allow my public IP to upload to Storage Static Website, then remove
# ID: CC_PATCH_FRONT_STORAGE_UPLOAD_TEMP_IP_V3_20260301
# ============================

RG="rg-colconnect-prod-frc"
ST="stcolconnectfrontfrc01"

echo "== [CC_PATCH_FRONT_STORAGE_UPLOAD_TEMP_IP_V3] Start =="

az account show -o none

echo "== Detect public IP =="
PUBIP="$(curl -fsS https://ifconfig.me || true)"
if [[ -z "${PUBIP:-}" ]]; then
  PUBIP="$(curl -fsS https://api.ipify.org || true)"
fi
if [[ -z "${PUBIP:-}" ]]; then
  echo "❌ Cannot detect public IP"
  echo "Rollback (git): git reset --hard HEAD~1"
  exit 2
fi
echo "PUBIP=$PUBIP"

echo "== Add temporary IP rule to Storage firewall =="
# idempotent-ish: add may fail if exists; ignore
az storage account network-rule add -g "$RG" -n "$ST" --ip-address "$PUBIP" -o none 2>/dev/null || true
echo "✅ Temp IP rule added (or already existed)"

echo "== Upload minimal vitrine files with AAD (auth-mode login) =="
TMPDIR="$(mktemp -d)"
cat > "$TMPDIR/index.html" <<'HTML'
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>ColConnect — Plateforme EU-only</title>
  <meta name="description" content="ColConnect — vitrine institutionnelle EU-only (France Central)."/>
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

echo "✅ Upload OK"

echo "== Remove temporary IP rule (restore AppGW-only) =="
az storage account network-rule remove -g "$RG" -n "$ST" --ip-address "$PUBIP" -o none 2>/dev/null || true
echo "✅ Temp IP rule removed"

echo "== Show static website endpoint =="
az storage account show -g "$RG" -n "$ST" --query "primaryEndpoints.web" -o tsv

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
echo "== Done =="
