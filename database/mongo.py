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
    Rend la création d'index idempotente:
    - si l'index existe déjà (même clés/options) -> OK
    - si conflit de nom/options -> on n'empêche pas le démarrage
    """
    try:
        collection.create_index(keys, **kwargs)
    except OperationFailure as e:
        # code 85 / IndexOptionsConflict : index déjà présent mais options/nom diffèrent
        if getattr(e, "code", None) == 85 or "IndexOptionsConflict" in str(e) or "already exists" in str(e):
            return
        raise


def ensure_indexes():
    db = get_db()

    # 1) settings: un seul document par collectivité
    # -> on évite 'name=' pour ne pas entrer en conflit avec collectivite_id_1 existant
    _safe_create_index(
        db.collectivites_settings,
        [("collectivite_id", ASCENDING)],
        unique=True,
    )

    # 2) arbitrages: tri rapide pour :last
    _safe_create_index(
        db.arbitrages,
        [("collectivite_id", ASCENDING), ("created_at_dt", DESCENDING)],
    )

    # 3) arbitrage_id: accès direct (si déjà existant autrement, on ignore le conflit)
    _safe_create_index(
        db.arbitrages,
        [("arbitrage_id", ASCENDING)],
        unique=True,
    )
