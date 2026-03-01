#!/usr/bin/env bash
set -euo pipefail

FILE="${1:-main.py}"
ts(){ date +"%Y%m%d_%H%M%S"; }

if [[ ! -f "$FILE" ]]; then
  echo "❌ File not found: $FILE" >&2
  exit 1
fi

BK="${FILE}.bak.$(ts)"
cp -a "$FILE" "$BK"
echo "✅ Backup: $BK"

python3 - "$FILE" <<'PY'
import re, sys, pathlib

p = pathlib.Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

# 1) Forcer include_in_schema=False sur /health si présent
def hide_health(m: re.Match) -> str:
    deco = m.group(0)
    if "include_in_schema" in deco:
        # remplace include_in_schema=... par False
        deco = re.sub(r'include_in_schema\s*=\s*(True|False)', 'include_in_schema=False', deco)
        return deco
    # injecte include_in_schema=False dans @app.get("...") ou @app.get('...')
    return deco[:-1] + ', include_in_schema=False)'

s2 = re.sub(r'@app\.get\(\s*([\'"])/health\1\s*\)', hide_health, s)
s2 = re.sub(r'@app\.get\(\s*([\'"])/health\1\s*,\s*([^\)]*)\)', lambda m: hide_health(m), s2)

# 2) Assurer que /api/health existe et est hidden, et renvoie {"ok": true}
#    - si existe, on le rend include_in_schema=False
#    - sinon on l'ajoute
api_health_deco_pat = re.compile(r'@app\.get\(\s*([\'"])/api/health\1\s*([^\)]*)\)\s*\n', re.M)
m = api_health_deco_pat.search(s2)

if m:
    deco = m.group(0)
    if "include_in_schema" in deco:
        deco2 = re.sub(r'include_in_schema\s*=\s*(True|False)', 'include_in_schema=False', deco)
    else:
        # inject before closing ")"
        deco2 = re.sub(r'\)\s*\n$', ', include_in_schema=False)\n', deco)
    s2 = s2[:m.start()] + deco2 + s2[m.end():]
else:
    # insère après le bloc /health si possible, sinon après app = FastAPI(...)
    insert = '\n\n@app.get("/api/health", include_in_schema=False)\n' \
             'def api_health_alias():\n' \
             '    return {"ok": True}\n'
    # après une def health existante
    mdef = re.search(r'@app\.get\(\s*[\'"]/health[\'"][^\)]*\)\s*\n(def\s+\w+\s*\([^\)]*\)\s*:\s*\n(?:[ \t].*\n)+)', s2, re.M)
    if mdef:
        end = mdef.end(1)
        s2 = s2[:end] + insert + s2[end:]
    else:
        mapp = re.search(r'^\s*app\s*=\s*FastAPI\s*\([^\)]*\)\s*$', s2, re.M)
        if mapp:
            end = mapp.end(0)
            s2 = s2[:end] + insert + s2[end:]
        else:
            # fallback: prepend top-level
            s2 = insert.strip("\n") + "\n\n" + s2

# 3) Si /api/health a déjà une fonction, on ne casse pas : on ne touche pas au body.
#    (On garantit juste include_in_schema=False, le reste est OK.)

if s2 == s:
    print("ℹ️ No changes needed (already normalized).")
else:
    p.write_text(s2, encoding="utf-8")
    print(f"✅ Patched: {p.name}")
PY

echo ""
echo "== Quick grep =="
grep -nE '@app\.get\("(/health|/api/health)"' "$FILE" || true
echo "Rollback (git): git reset --hard HEAD~1"
