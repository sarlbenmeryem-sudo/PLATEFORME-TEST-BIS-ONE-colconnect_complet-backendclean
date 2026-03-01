#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

ts() { date +"%Y%m%d_%H%M%S"; }

# 1) Trouver le fichier FastAPI
TARGET="$(grep -RIl --include='*.py' -E '^\s*app\s*=\s*FastAPI\s*\(' "$ROOT" 2>/dev/null | head -n 1 || true)"
if [[ -z "${TARGET:-}" ]]; then
  TARGET="$(grep -RIl --include='*.py' -E 'FastAPI\s*\(' "$ROOT" 2>/dev/null | head -n 1 || true)"
fi
if [[ -z "${TARGET:-}" ]]; then
  echo "❌ Impossible de trouver un fichier FastAPI(...) sous $ROOT" >&2
  exit 1
fi

echo "== Target file: $TARGET =="

BK="${TARGET}.bak.$(ts)"
cp -a "$TARGET" "$BK"
echo "✅ Backup: $BK"

python3 - "$TARGET" <<'PY'
import re, sys, pathlib

path = pathlib.Path(sys.argv[1])
txt = path.read_text(encoding="utf-8")

# 1) Patch app = FastAPI(...)
m = re.search(r'(^\s*app\s*=\s*FastAPI\s*\()([^)]*)(\)\s*)', txt, flags=re.M)
if not m:
    raise SystemExit("❌ Pattern 'app = FastAPI(' non trouvé.")

before, inside, after = m.group(1), m.group(2), m.group(3)

def upsert_kw(inside: str, key: str, value: str) -> str:
    pat = re.compile(r'(\b' + re.escape(key) + r'\s*=\s*)([^,]+)')
    if pat.search(inside):
        return pat.sub(r'\1' + value, inside, count=1)
    inside = inside.strip()
    if inside and not inside.endswith(','):
        inside += ', '
    return inside + f'{key}={value}'

inside2 = inside
inside2 = upsert_kw(inside2, 'docs_url', '"/api/docs"')
inside2 = upsert_kw(inside2, 'openapi_url', '"/api/openapi.json"')
inside2 = upsert_kw(inside2, 'redoc_url', 'None')

txt = txt[:m.start()] + before + inside2 + after + txt[m.end():]

# 2) Ajouter /api/health alias
if not re.search(r'@app\.get\(\s*[\'"]\/api\/health[\'"]', txt):
    hm = re.search(
        r'@app\.get\(\s*[\'"]\/health[\'"][^)]*\)\s*\n(\s*)def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(',
        txt, flags=re.M
    )
    if hm:
        indent = hm.group(1)
        fn = hm.group(2)

        # insère juste après la définition du handler /health (simple : après le bloc /health)
        start = hm.start()
        # fin approximative: prochain décorateur @app ou EOF
        nxt = re.search(r'\n@app\.', txt[hm.end():])
        end = hm.end() + (nxt.start() if nxt else len(txt) - hm.end())

        insert = (
            f'\n{indent}@app.get("/api/health", include_in_schema=False)\n'
            f'{indent}def api_health_alias():\n'
            f'{indent}    return {fn}()\n'
        )
        txt = txt[:end] + insert + txt[end:]
    else:
        # fallback: créer /health et /api/health si /health n'existe pas
        txt += '\n\n@app.get("/health")\ndef health():\n    return {"ok": True}\n'
        txt += '\n@app.get("/api/health", include_in_schema=False)\ndef api_health_alias():\n    return {"ok": True}\n'

path.write_text(txt, encoding="utf-8")
print("✅ Patch applied:", path)
PY

echo ""
echo "== Quick grep (sanity) =="
grep -nE 'app\s*=\s*FastAPI|/api/docs|/api/openapi\.json|/api/health|/health' "$TARGET" | head -n 80 || true

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
