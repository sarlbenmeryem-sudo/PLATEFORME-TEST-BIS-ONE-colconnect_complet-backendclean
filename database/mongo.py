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
    """
    À appeler au démarrage pour garantir les indexes nécessaires (idempotent).
    """
    db = get_db()

    # Arbitrages: recherche du dernier arbitrage + filtres par collectivité/version
    db.arbitrages.create_index([("collectivite_id", ASCENDING), ("created_at", DESCENDING)])
    db.arbitrages.create_index([("collectivite_id", ASCENDING), ("engine_version", ASCENDING)])
    db.arbitrages.create_index([("payload_hash", ASCENDING)])

    # Settings: un doc par collectivité
    db.collectivites_settings.create_index([("collectivite_id", ASCENDING)], unique=True)
