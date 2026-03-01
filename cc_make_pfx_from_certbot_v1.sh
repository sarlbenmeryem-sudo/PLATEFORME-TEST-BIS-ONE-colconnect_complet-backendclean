#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${1:-api.colconnect.fr}"
OUT="${2:-/mnt/c/Users/benme/Desktop/${DOMAIN}.pfx}"

LIVE="/etc/letsencrypt/live/${DOMAIN}"
FULLCHAIN="${LIVE}/fullchain.pem"
PRIVKEY="${LIVE}/privkey.pem"

echo "== Make PFX from Certbot =="
echo "DOMAIN=$DOMAIN"
echo "FULLCHAIN=$FULLCHAIN"
echo "PRIVKEY=$PRIVKEY"
echo "OUT=$OUT"

if [[ ! -f "$FULLCHAIN" || ! -f "$PRIVKEY" ]]; then
  echo "❌ Missing certbot files for $DOMAIN in $LIVE" >&2
  exit 1
fi

echo ""
echo "== Create PKCS#12 (you will be prompted for export password) =="
openssl pkcs12 -export \
  -out "$OUT" \
  -inkey "$PRIVKEY" \
  -in "$FULLCHAIN" \
  -name "$DOMAIN"

echo ""
echo "== Verify PFX (you will be prompted for import password) =="
openssl pkcs12 -in "$OUT" -info -noout >/dev/null

echo "✅ OK: $OUT"
echo "Rollback (git): git reset --hard HEAD~1"
