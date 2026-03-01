#!/usr/bin/env bash
set -euo pipefail

TARGET="./cc_appgw_enable_https_from_pfx_v1.sh"
DEFAULT_RULE_NAME="rule-https-api-to-backend"

ts(){ date +"%Y%m%d_%H%M%S"; }

if [[ ! -f "$TARGET" ]]; then
  echo "❌ Target not found: $TARGET" >&2
  exit 1
fi

BK="${TARGET}.bak.define_rule_name.$(ts)"
cp -a "$TARGET" "$BK"
echo "✅ Backup: $BK"

python3 - "$TARGET" "$DEFAULT_RULE_NAME" <<'PY'
import re, sys, pathlib
path = pathlib.Path(sys.argv[1])
default_rule = sys.argv[2]
s = path.read_text(encoding="utf-8")

# If RULE_NAME already defined anywhere, do nothing.
if re.search(r'^\s*RULE_NAME\s*=', s, flags=re.M):
    print("ℹ️ RULE_NAME already present, nothing to do.")
    sys.exit(0)

# Best place: right after RULE_PRIORITY if present, else after APPGW line, else after set -euo pipefail
insert_line = f'RULE_NAME="${{RULE_NAME:-{default_rule}}}"\n'

m = re.search(r'(^\s*RULE_PRIORITY=.*\n)', s, flags=re.M)
if m:
    s = s.replace(m.group(1), m.group(1) + insert_line, 1)
else:
    m2 = re.search(r'(^\s*APPGW=.*\n)', s, flags=re.M)
    if m2:
        s = s.replace(m2.group(1), m2.group(1) + insert_line, 1)
    else:
        m3 = re.search(r'(^\s*set -euo pipefail\s*\n)', s, flags=re.M)
        if m3:
            s = s.replace(m3.group(1), m3.group(1) + insert_line, 1)
        else:
            s = insert_line + s

path.write_text(s, encoding="utf-8")
print("✅ Injected RULE_NAME")
PY

echo ""
echo "== Sanity grep =="
grep -nE 'RULE_NAME=|RULE_PRIORITY=' "$TARGET" | head -n 50 || true

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
