import os
from pymongo import MongoClient, ASCENDING, DESCENDING

_MONGO_URI = os.getenv("MONGO_URI", "")
_client = MongoClient(_MONGO_URI) if _MONGO_URI else None


def get_db():
    if not _client:
        raise RuntimeError("MongoDB non configuré (MONGO_URI manquant)")
    return _client["colconnect"]


def ensure_indexes():
    db = get_db()

    # 1️⃣ Un seul settings par collectivité
    db.collectivites_settings.create_index(
        [("collectivite_id", ASCENDING)],
        unique=True,
        name="uniq_collectivite_settings"
    )

    # 2️⃣ Index tri arbitrage:last
    db.arbitrages.create_index(
        [("collectivite_id", ASCENDING), ("created_at_dt", DESCENDING)],
        name="idx_collectivite_created_desc"
    )

    # 3️⃣ Accès direct par arbitrage_id
    db.arbitrages.create_index(
        [("arbitrage_id", ASCENDING)],
        unique=True,
        name="uniq_arbitrage_id"
    )
