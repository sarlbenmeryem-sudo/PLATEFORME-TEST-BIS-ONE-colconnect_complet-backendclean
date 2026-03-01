#!/usr/bin/env bash
set -euo pipefail
REQ="${1:-requirements.txt}"

if [[ ! -f "$REQ" ]]; then
  echo "❌ Not found: $REQ" >&2
  exit 1
fi

ts(){ date +"%Y%m%d_%H%M%S"; }
BK="${REQ}.bak.$(ts)"
cp -a "$REQ" "$BK"
echo "✅ Backup: $BK"

if grep -qiE '^gunicorn([=<>!~].*)?$' "$REQ"; then
  echo "✅ gunicorn already present in $REQ"
else
  echo "" >> "$REQ"
  echo "gunicorn>=21.2.0" >> "$REQ"
  echo "✅ Added gunicorn to $REQ"
fi

echo "Rollback (git): git reset --hard HEAD~1"
