from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import uuid
from typing import Any, Dict, Optional

from database.mongo import get_db
from engine.arbitrage_v2 import calculer_arbitrage_2_0, ENGINE_VERSION


def _utc_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _payload_hash(payload: Dict[str, Any]) -> str:
    # Hash stable : tri des clés + ensure_ascii
    raw = json.dumps(payload, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _default_settings() -> Dict[str, float]:
    return {"poids_climat": 0.4, "poids_education": 0.3, "poids_financier": 0.3}


def get_settings_for_collectivite(collectivite_id: str) -> Dict[str, float]:
    db = get_db()
    doc = db.collectivites_settings.find_one({"collectivite_id": collectivite_id}, projection={"_id": 0})
    if not doc:
        return _default_settings()
    # On ne garde que les champs attendus
    return {
        "poids_climat": float(doc.get("poids_climat", 0.4)),
        "poids_education": float(doc.get("poids_education", 0.3)),
        "poids_financier": float(doc.get("poids_financier", 0.3)),
    }


def upsert_settings(collectivite_id: str, settings: Dict[str, Any]) -> Dict[str, Any]:
    db = get_db()
    doc = {
        "collectivite_id": collectivite_id,
        "poids_climat": float(settings["poids_climat"]),
        "poids_education": float(settings["poids_education"]),
        "poids_financier": float(settings["poids_financier"]),
        "updated_at": _utc_iso(),
    }
    db.collectivites_settings.update_one(
        {"collectivite_id": collectivite_id},
        {"$set": doc},
        upsert=True,
    )
    return doc


def run_arbitrage(
    collectivite_id: str,
    payload_dict: Dict[str, Any],
    triggered_by: str,
) -> Dict[str, Any]:
    db = get_db()

    arbitrage_id = f"arb-{datetime.utcnow().year}-{uuid.uuid4().hex[:8]}"
    created_at = _utc_iso()

    payload_hash = _payload_hash(payload_dict)
    weights = get_settings_for_collectivite(collectivite_id)

    calc = calculer_arbitrage_2_0(payload_dict, weights=weights)

    out = {
        "arbitrage_id": arbitrage_id,
        "collectivite_id": collectivite_id,
        "mandat": calc["mandat"],
        "synthese": calc["synthese"],
        "projets": calc["projets"],
        "audit": {
            "engine_version": ENGINE_VERSION,
            "triggered_by": triggered_by,
            "payload_hash": payload_hash,
            "timestamp_utc": created_at,
        },
        # champs DB utiles (debug/audit)
        "created_at": created_at,
        "engine_version": ENGINE_VERSION,
        "triggered_by": triggered_by,
        "payload_hash": payload_hash,
        "weights": weights,
    }

    db.arbitrages.insert_one(out)
    # projection _id supprimée au GET, donc pas besoin de conversion ObjectId ici
    return out


def get_last_arbitrage(collectivite_id: str) -> Dict[str, Any]:
    db = get_db()
    doc = db.arbitrages.find_one(
        {"collectivite_id": collectivite_id},
        sort=[("created_at", -1)],
        projection={"_id": 0},
    )
    if not doc:
        raise KeyError("Aucun arbitrage trouvé pour cette collectivité")
    return doc
