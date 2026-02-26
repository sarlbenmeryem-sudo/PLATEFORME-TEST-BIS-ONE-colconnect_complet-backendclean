import os
from pymongo import MongoClient, ASCENDING, DESCENDING

_MONGO_URI = os.getenv("MONGO_URI", "")
_client = MongoClient(_MONGO_URI) if _MONGO_URI else None

_DB_NAME = os.getenv("MONGO_DB", "colconnect")


def get_db():
    if not _client:
        raise RuntimeError("MongoDB non configuré (MONGO_URI manquant)")
    return _client[_DB_NAME]


def ensure_indexes():
    db = get_db()

    # Nouveau tri fiable (datetime BSON)
    db.arbitrages.create_index([("collectivite_id", ASCENDING), ("created_at_dt", DESCENDING)])

    # Legacy (si des docs ont created_at en string)
    db.arbitrages.create_index([("collectivite_id", ASCENDING), ("created_at", DESCENDING)])

    db.arbitrages.create_index([("collectivite_id", ASCENDING), ("engine_version", ASCENDING)])
    db.arbitrages.create_index([("payload_hash", ASCENDING)])

    db.collectivites_settings.create_index([("collectivite_id", ASCENDING)], unique=True)
