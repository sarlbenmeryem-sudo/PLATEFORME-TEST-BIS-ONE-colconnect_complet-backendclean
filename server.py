# Wrapper pour Render: Render lance "uvicorn server:app"
from main import app  # noqa: F401

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
