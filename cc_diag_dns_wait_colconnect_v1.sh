#!/usr/bin/env bash
set -euo pipefail

DOMAIN="colconnect.fr"
EXPECTED_IP="20.74.38.64"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing $1" >&2; exit 1; }; }
need dig
need curl

echo "== Waiting DNS A record for ${DOMAIN} -> ${EXPECTED_IP} =="

for i in $(seq 1 60); do
  ip="$(dig +short A "$DOMAIN" | head -n 1 || true)"
  echo "[$i] A ${DOMAIN} = ${ip:-<none>}"
  if [[ "$ip" == "$EXPECTED_IP" ]]; then
    echo "✅ DNS A record OK"
    break
  fi
  sleep 20
done

echo ""
echo "== HTTP headers root (after DNS) =="
curl -sSI "https://${DOMAIN}/" | sed -n '1,15p' || true
echo ""
echo "== HTTP headers www (after DNS) =="
curl -sSI "https://www.${DOMAIN}/" | sed -n '1,15p' || true

echo ""
echo "== Done =="
