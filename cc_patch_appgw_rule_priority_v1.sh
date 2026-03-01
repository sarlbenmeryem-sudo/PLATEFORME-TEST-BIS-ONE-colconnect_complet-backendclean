#!/usr/bin/env bash
set -euo pipefail

TARGET="./cc_appgw_enable_https_from_pfx_v1.sh"
PRIORITY_DEFAULT="100"

ts() { date +"%Y%m%d_%H%M%S"; }

if [[ ! -f "$TARGET" ]]; then
  echo "❌ Target not found: $TARGET" >&2
  exit 1
fi

BK="${TARGET}.bak.$(ts)"
cp -a "$TARGET" "$BK"
echo "✅ Backup: $BK"

python3 - "$TARGET" "$PRIORITY_DEFAULT" <<'PY'
import re, sys, pathlib

path = pathlib.Path(sys.argv[1])
prio = sys.argv[2]
s = path.read_text(encoding="utf-8")

# 1) Ensure a RULE_PRIORITY var exists near other vars (best effort)
if "RULE_PRIORITY=" not in s:
    # Try to insert after APPGW=... line
    m = re.search(r'(^APPGW=.*\n)', s, flags=re.M)
    if m:
        insert = m.group(1) + f'RULE_PRIORITY="${{RULE_PRIORITY:-{prio}}}"\n'
        s = s.replace(m.group(1), insert, 1)
    else:
        # fallback: prepend at top after set -euo pipefail
        m2 = re.search(r'(^set -euo pipefail\s*\n)', s, flags=re.M)
        if m2:
            insert = m2.group(1) + f'RULE_PRIORITY="${{RULE_PRIORITY:-{prio}}}"\n'
            s = s.replace(m2.group(1), insert, 1)
        else:
            s = f'RULE_PRIORITY="${{RULE_PRIORITY:-{prio}}}"\n' + s

# 2) Add priority to "create" call: az network application-gateway rule create ...
# Only if not already present on that line
def add_priority_to_rule_create(text: str) -> str:
    lines = text.splitlines(True)
    out = []
    for line in lines:
        if re.search(r'\baz network application-gateway rule create\b', line) and "--priority" not in line:
            # append priority as a new token; handle line continuation styles
            if line.rstrip().endswith("\\"):
                out.append(line)
                out.append(f'    --priority "$RULE_PRIORITY" \\\n')
            else:
                out.append(line.rstrip("\n") + f' --priority "$RULE_PRIORITY"\n')
        else:
            out.append(line)
    return "".join(out)

s2 = add_priority_to_rule_create(s)

# 3) Ensure "update existing rule priority" happens before create (idempotent)
# We inject a block right before the rule create section header if found.
inject_block = r'''
echo ""
echo "== Ensure routing rule priority (required by API >= 2021-08-01) =="
if az network application-gateway rule show -g "$RG" --gateway-name "$APPGW" -n "$RULE_NAME" >/dev/null 2>&1; then
  echo "ℹ️ Rule exists: $RULE_NAME -> set priority=$RULE_PRIORITY"
  az network application-gateway rule update -g "$RG" --gateway-name "$APPGW" -n "$RULE_NAME" --priority "$RULE_PRIORITY" >/dev/null
fi
'''

# Heuristic: find the section that mentions routing rule
if "Ensure routing rule" in s2 and "RequestRoutingRulePriorityCannotBeEmpty" not in s2:
    # try insert after the "Ensure routing rule" echo line
    s3 = re.sub(
        r'(echo\s+"==\s*Ensure routing rule[^"]*==".*\n)',
        r'\1' + inject_block,
        s2,
        count=1,
        flags=re.M
    )
else:
    # fallback: add block before first occurrence of "az network application-gateway rule create"
    s3 = re.sub(
        r'(^\s*az network application-gateway rule create\b)',
        inject_block + r'\n\1',
        s2,
        count=1,
        flags=re.M
    )

path.write_text(s3, encoding="utf-8")
print(f"✅ Patched: {path}")
PY

echo ""
echo "== Sanity grep =="
grep -nE "RULE_PRIORITY=|--priority|Ensure routing rule priority" "$TARGET" | head -n 50 || true

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
