import os
from pymongo import MongoClient, ASCENDING, DESCENDING
from pymongo.errors import OperationFailure

_MONGO_URI = os.getenv("MONGO_URI", "")
_client = MongoClient(_MONGO_URI) if _MONGO_URI else None


def get_db():
    if not _client:
        raise RuntimeError("MongoDB non configuré (MONGO_URI manquant)")
    return _client["colconnect"]


def _safe_create_index(collection, keys, **kwargs):
    """
    Création d'index idempotente:
    - si l'index existe déjà -> OK
    - si conflit d'options/nom (IndexOptionsConflict) -> on ignore pour ne pas bloquer le démarrage
    """
    try:
        collection.create_index(keys, **kwargs)
    except OperationFailure as e:
        msg = str(e)
        if getattr(e, "code", None) == 85 or "IndexOptionsConflict" in msg or "already exists" in msg:
            return
        raise


def ensure_indexes():
    db = get_db()

    # Settings: un seul doc par collectivité (évite name= pour ne pas conflit avec collectivite_id_1)
    _safe_create_index(db.collectivites_settings, [("collectivite_id", ASCENDING)], unique=True)

    # Arbitrages: tri rapide pour :last
    _safe_create_index(db.arbitrages, [("collectivite_id", ASCENDING), ("created_at_dt", DESCENDING)])

    # Arbitrage ID: accès direct
    _safe_create_index(db.arbitrages, [("arbitrage_id", ASCENDING)], unique=True)
