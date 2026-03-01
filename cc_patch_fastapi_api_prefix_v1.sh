#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

ts() { date +"%Y%m%d_%H%M%S"; }

# 1) Trouver un fichier plausible qui contient "FastAPI("
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

python3 - <<'PY'
import re, sys, pathlib

path = pathlib.Path(sys.argv[1])
txt = path.read_text(encoding="utf-8")

# --- A) Forcer docs/openapi sous /api/* (sans casser /health) ---
# Cas 1: app = FastAPI(...)
m = re.search(r'(^\s*app\s*=\s*FastAPI\s*\()([^)]*)(\)\s*)', txt, flags=re.M)
if not m:
    print("❌ Pattern 'app = FastAPI(' non trouvé de façon fiable.", file=sys.stderr)
    sys.exit(2)

before, inside, after = m.group(1), m.group(2), m.group(3)

def upsert_kw(inside: str, key: str, value: str) -> str:
    # remplace key=... si existe, sinon ajoute
    pat = re.compile(r'(\b' + re.escape(key) + r'\s*=\s*)([^,]+)')
    if pat.search(inside):
        inside = pat.sub(r'\1' + value, inside, count=1)
    else:
        inside = inside.strip()
        if inside and not inside.endswith(','):
            inside += ', '
        inside += f'{key}={value}'
    return inside

inside2 = inside
inside2 = upsert_kw(inside2, 'docs_url', '"/api/docs"')
inside2 = upsert_kw(inside2, 'openapi_url', '"/api/openapi.json"')
# Optionnel: on garde redoc off (souvent inutile)
inside2 = upsert_kw(inside2, 'redoc_url', 'None')

txt = txt[:m.start()] + before + inside2 + after + txt[m.end():]

# --- B) Ajouter alias /api/health qui renvoie la même chose que /health ---
# On cherche une fonction associée à @app.get("/health")
hm = re.search(
    r'@app\.get\(\s*[\'"]\/health[\'"][^)]*\)\s*\n(\s*)def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(',
    txt,
    flags=re.M
)

if hm:
    indent = hm.group(1)
    fn = hm.group(2)

    # Si /api/health existe déjà, ne rien faire
    if re.search(r'@app\.get\(\s*[\'"]\/api\/health[\'"]', txt):
        pass
    else:
        insert = (
            f'\n{indent}@app.get("/api/health", include_in_schema=False)\n'
            f'{indent}def api_health_alias():\n'
            f'{indent}    return {fn}()\n'
        )
        # insérer juste après la définition complète de la fonction health (approche simple : après la ligne "def fn(...):")
        # On insère après le premier "return" de cette fonction si possible, sinon après la signature.
        block_start = hm.start()
        # trouver fin de fonction approximative: prochain décorateur @app ou fin de fichier
        nxt = re.search(r'\n@app\.', txt[hm.end():])
        end = hm.end() + (nxt.start() if nxt else len(txt) - hm.end())
        func_block = txt[block_start:end]
        # insérer à la fin du bloc
        txt = txt[:end] + insert + txt[end:]
else:
    # si on n'a pas /health, on ajoute une implémentation minimale
    if not re.search(r'@app\.get\(\s*[\'"]\/api\/health[\'"]', txt):
        txt += '\n\n@app.get("/health")\ndef health():\n    return {"ok": True}\n'
        txt += '\n@app.get("/api/health", include_in_schema=False)\ndef api_health_alias():\n    return {"ok": True}\n'

path.write_text(txt, encoding="utf-8")
print("✅ Patch applied.")
PY "$TARGET"

echo ""
echo "== Quick local grep =="
grep -nE 'app\s*=\s*FastAPI|/api/docs|/api/openapi|/api/health|/health' "$TARGET" | head -n 40 || true

echo ""
echo "Rollback (git): git reset --hard HEAD~1"
