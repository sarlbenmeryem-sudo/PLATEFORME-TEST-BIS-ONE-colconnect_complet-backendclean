from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import uuid
from typing import Any, Dict

from database.mongo import get_db
from engine.arbitrage_v2 import calculer_arbitrage_2_0, ENGINE_VERSION


def _utc_now_dt() -> datetime:
    return datetime.now(timezone.utc)


def _utc_iso(dt: datetime | None = None) -> str:
    dt = dt or _utc_now_dt()
    return dt.isoformat().replace("+00:00", "Z")


def _payload_hash(payload: Dict[str, Any]) -> str:
    raw = json.dumps(payload, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _default_settings() -> Dict[str, float]:
    return {"poids_climat": 0.4, "poids_education": 0.3, "poids_financier": 0.3}


def get_settings_for_collectivite(collectivite_id: str) -> Dict[str, float]:
    db = get_db()
    doc = db.collectivites_settings.find_one({"collectivite_id": collectivite_id}, projection={"_id": 0})
    if not doc:
        return _default_settings()
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


def _normalize_arbitrage_doc(doc: Dict[str, Any]) -> Dict[str, Any]:
    """
    Backward-compat: si 'audit' manque (anciens docs), on le reconstruit.
    """
    # created_at peut être string ISO (nouveau) ou datetime BSON (ancien)
    created_at_dt = doc.get("created_at_dt")
    created_at = doc.get("created_at")

    if isinstance(created_at_dt, datetime):
        ts = _utc_iso(created_at_dt)
    elif isinstance(created_at, datetime):
        ts = _utc_iso(created_at)
    elif isinstance(created_at, str) and created_at:
        ts = created_at
    else:
        ts = _utc_iso()

    engine_version = doc.get("engine_version") or doc.get("audit", {}).get("engine_version") or ENGINE_VERSION
    triggered_by = doc.get("triggered_by") or doc.get("audit", {}).get("triggered_by") or "unknown"
    payload_hash = doc.get("payload_hash") or doc.get("audit", {}).get("payload_hash") or "unknown"

    if "audit" not in doc or not isinstance(doc.get("audit"), dict):
        doc["audit"] = {
            "engine_version": engine_version,
            "triggered_by": triggered_by,
            "payload_hash": payload_hash,
            "timestamp_utc": ts,
        }
    else:
        # Complète les champs manquants
        doc["audit"].setdefault("engine_version", engine_version)
        doc["audit"].setdefault("triggered_by", triggered_by)
        doc["audit"].setdefault("payload_hash", payload_hash)
        doc["audit"].setdefault("timestamp_utc", ts)

    # Garantit les clés "top-level" utilisées par l'API
    doc.setdefault("engine_version", engine_version)
    doc.setdefault("triggered_by", triggered_by)
    doc.setdefault("payload_hash", payload_hash)

    return doc


def run_arbitrage(
    collectivite_id: str,
    payload_dict: Dict[str, Any],
    triggered_by: str,
) -> Dict[str, Any]:
    db = get_db()

    arbitrage_id = f"arb-{datetime.utcnow().year}-{uuid.uuid4().hex[:8]}"
    now_dt = _utc_now_dt()
    created_at = _utc_iso(now_dt)

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
        # DB fields
        "created_at": created_at,      # string ISO
        "created_at_dt": now_dt,       # BSON datetime (tri fiable)
        "engine_version": ENGINE_VERSION,
        "triggered_by": triggered_by,
        "payload_hash": payload_hash,
        "weights": weights,
    }

    db.arbitrages.insert_one(out)
    return out


def get_last_arbitrage(collectivite_id: str) -> Dict[str, Any]:
    db = get_db()
    doc = db.arbitrages.find_one(
        {"collectivite_id": collectivite_id},
        sort=[("created_at_dt", -1), ("created_at", -1)],
        projection={"_id": 0},
    )
    if not doc:
        raise KeyError("Aucun arbitrage trouvé pour cette collectivité")

    return _normalize_arbitrage_doc(doc)
