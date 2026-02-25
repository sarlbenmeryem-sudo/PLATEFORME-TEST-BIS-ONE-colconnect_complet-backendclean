import re
from pathlib import Path

p = Path("server.py")
s = p.read_text(encoding="utf-8")

needle = '@app.post("/api/collectivites/{collectivite_id}/arbitrage:run")'
idxs = [m.start() for m in re.finditer(re.escape(needle), s)]
if not idxs:
    raise SystemExit("ERREUR: route arbitrage:run introuvable dans server.py")

def find_block_end(text, start):
    m = re.search(r"\n@app\.(get|post|put|delete|patch)\(", text[start+1:])
    return start + 1 + m.start() if m else len(text)

# Supprime toutes les occurrences sauf la dernière
parts = []
cursor = 0
for start in idxs[:-1]:
    end = find_block_end(s, start)
    parts.append(s[cursor:start])
    cursor = end
parts.append(s[cursor:])
s2 = "".join(parts)

# Ajoute Body dans l'import fastapi si absent
if re.search(r"from fastapi import .*\\bBody\\b", s2) is None:
    s2 = re.sub(
        r"from fastapi import ([^\n]+)",
        lambda m: m.group(0) if "Body" in m.group(1) else f"from fastapi import {m.group(1)}, Body",
        s2,
        count=1,
    )

# Récupère le bloc conservé (la dernière route)
k = s2.rfind(needle)
block_end = find_block_end(s2, k)
block = s2[k:block_end]

# Force la signature: payload = Body(...)
block = re.sub(
    r"def\\s+run_arbitrage\\([^\\)]*\\):",
    "def run_arbitrage(collectivite_id: str, payload: dict = Body(...)):",
    block,
    count=1,
)

s3 = s2[:k] + block + s2[block_end:]
p.write_text(s3, encoding="utf-8")

print("OK: arbitrage:run -> payload JSON body + doublons supprimés")
