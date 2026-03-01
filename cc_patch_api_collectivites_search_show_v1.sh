#!/usr/bin/env bash
set -euo pipefail

# ============================
# Patch: Add Collectivites search + show endpoints
# ID: CC_PATCH_API_COLLECTIVITES_SEARCH_SHOW_V1_20260301
# ============================

FILE="server.py"

if [[ ! -f "$FILE" ]]; then
  echo "❌ server.py not found"
  exit 1
fi

echo "== Injecting Collectivites endpoints into $FILE =="

if grep -q "CC_PATCH_COLLECTIVITES_V1" "$FILE"; then
  echo "ℹ️ Patch already applied"
  exit 0
fi

cat >> "$FILE" <<'PYCODE'

# ============================
# CC_PATCH_COLLECTIVITES_V1
# ============================

from fastapi import Query, HTTPException
from bson import ObjectId
from typing import List

def serialize_collectivite(doc):
    doc["id"] = str(doc["_id"])
    del doc["_id"]
    return doc

@app.get("/api/collectivites/search")
async def search_collectivites(
    q: str = Query(..., min_length=2),
    limit: int = Query(10, ge=1, le=50)
):
    regex = {"$regex": q, "$options": "i"}
    cursor = db.collectivites.find(
        {"nom": regex},
        {"nom": 1, "departement": 1}
    ).limit(limit)

    results = [serialize_collectivite(doc) async for doc in cursor]
    return {"count": len(results), "items": results}


@app.get("/api/collectivites/{collectivite_id}")
async def get_collectivite(collectivite_id: str):
    try:
        obj_id = ObjectId(collectivite_id)
    except:
        raise HTTPException(status_code=400, detail="Invalid ID format")

    doc = await db.collectivites.find_one({"_id": obj_id})

    if not doc:
        raise HTTPException(status_code=404, detail="Collectivite not found")

    return serialize_collectivite(doc)

# ============================
PYCODE

echo "== Creating Mongo index for search (nom) =="

cat > cc_mongo_index_collectivites_v1.py <<'PYCODE'
import asyncio
from motor.motor_asyncio import AsyncIOMotorClient
import os

MONGO_URI = os.getenv("MONGO_URI")
DB_NAME = os.getenv("DB_NAME", "colconnect")

async def main():
    client = AsyncIOMotorClient(MONGO_URI)
    db = client[DB_NAME]
    await db.collectivites.create_index("nom")
    print("Index created on 'nom'")

asyncio.run(main())
PYCODE

echo ""
echo "✅ Patch applied"
echo "➡️ Next: rebuild & deploy backend"
echo "Rollback (git): git reset --hard HEAD~1"
