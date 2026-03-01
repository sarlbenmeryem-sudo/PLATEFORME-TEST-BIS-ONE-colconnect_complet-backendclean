#!/usr/bin/env bash
set -euo pipefail

echo "== Search likely TLS files on Desktop (depth 8) =="
find "/mnt/c/Users/benme/Desktop" -maxdepth 8 -type f \
  \( -iname "privkey.pem" -o -iname "fullchain.pem" -o -iname "cert.pem" -o -iname "chain.pem" -o -iname "certificate.crt" -o -iname "*.crt" -o -iname "*.pem" -o -iname "*.key" -o -iname "*.pfx" -o -iname "*.p12" \) \
  2>/dev/null | head -n 200

echo ""
echo "== Search in current project (.) =="
find "." -maxdepth 6 -type f \
  \( -iname "privkey.pem" -o -iname "fullchain.pem" -o -iname "cert.pem" -o -iname "chain.pem" -o -iname "certificate.crt" -o -iname "*.crt" -o -iname "*.pem" -o -iname "*.key" -o -iname "*.pfx" -o -iname "*.p12" \) \
  2>/dev/null | head -n 200

echo ""
echo "== Done =="
echo "Rollback (git): git reset --hard HEAD~1"
