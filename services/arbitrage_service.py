from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import uuid
from typing import Any, Dict

from database.mongo import get_db
from engine.arbitrage_v2 import calculer_arbitrage_2_0, ENGINE_VERSION

from schemas.arbitrage import ArbitrageRunOut


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



def _to_api_out(doc: Dict[str, Any]) -> Dict[str, Any]:
    """Construit le dict conforme à ArbitrageRunOut (ou le plus proche possible)."""
    doc = _normalize_arbitrage_doc(doc)

    # Champs top-level
    out = {
        "arbitrage_id": doc.get("arbitrage_id", "unknown"),
        "collectivite_id": doc.get("collectivite_id", "unknown"),
        "mandat": doc.get("mandat", "unknown"),
        "synthese": doc.get("synthese") or {
            "budget_max": 0.0,
            "budget_retenu": 0.0,
            "budget_restant": 0.0,
            "nb_projets_total": 0,
            "nb_projets_retenus": 0,
        },
        "projets": doc.get("projets") or [],
        "audit": doc.get("audit") or {
            "engine_version": ENGINE_VERSION,
            "triggered_by": "unknown",
            "payload_hash": "unknown",
            "timestamp_utc": _utc_iso(),
        },
    }

    # Normalisation projets (legacy-safe)
    norm_projets = []
    for p in out["projets"]:
        if not isinstance(p, dict):
            continue
        norm_projets.append({
            "id": p.get("id", "unknown"),
            "nom": p.get("nom", "unknown"),
            "cout_ttc": float(p.get("cout_ttc", 0.0) or 0.0),
            "annee_realisation": int(p.get("annee_realisation", 0) or 0),
            "score": float(p.get("score", 0.0) or 0.0),
            "retenu": bool(p.get("retenu", False)),
            "details_score": p.get("details_score") or {},
        })
    out["projets"] = norm_projets

    # Recalcule synthese si manquante/incomplète
    s = out["synthese"] if isinstance(out["synthese"], dict) else {}
    if not all(k in s for k in ("budget_max","budget_retenu","budget_restant","nb_projets_total","nb_projets_retenus")):
        budget_retenu = sum(p["cout_ttc"] for p in out["projets"] if p.get("retenu"))
        out["synthese"] = {
            "budget_max": float(s.get("budget_max", 0.0) or 0.0),
            "budget_retenu": float(budget_retenu),
            "budget_restant": float((s.get("budget_max", 0.0) or 0.0) - budget_retenu),
            "nb_projets_total": len(out["projets"]),
            "nb_projets_retenus": sum(1 for p in out["projets"] if p.get("retenu")),
        }

    return out


def get_last_arbitrage_out(collectivite_id: str) -> Dict[str, Any]:
    """
    Retourne un arbitrage *conforme* au schéma ArbitrageRunOut.
    On scanne les 20 derniers docs et on garde le premier qui valide.
    """
    db = get_db()
    cursor = db.arbitrages.find(
        {"collectivite_id": collectivite_id, "engine_version": "2.0.0"},
        projection={"_id": 0},
    ).sort([("created_at_dt", -1), ("created_at", -1)]).limit(20)

    last_seen = None
    for doc in cursor:
        last_seen = doc
        try:
            out = _to_api_out(doc)
            # Validation stricte de la réponse
            ArbitrageRunOut.model_validate(out)
            return out
        except Exception:
            continue

    if not last_seen:
        raise KeyError("Aucun arbitrage trouvé pour cette collectivité")

    # fallback ultime: normaliser + retourner (peut encore échouer si doc vraiment incohérent)
    out = _to_api_out(last_seen)
    ArbitrageRunOut.model_validate(out)
    return out

def get_last_arbitrage(collectivite_id: str) -> Dict[str, Any]:
    db = get_db()

    # On parcourt les docs les plus récents et on normalise.
    # But: être robuste si l'historique contient des formats hétérogènes (audit manquant, dates mixtes).
    cursor = db.arbitrages.find(
        {"collectivite_id": collectivite_id},
        projection={"_id": 0},
    ).sort([("created_at_dt", -1), ("created_at", -1)]).limit(20)

    last = None
    for doc in cursor:
        last = doc
        try:
            return _normalize_arbitrage_doc(doc)
        except Exception:
            # si un doc est vraiment corrompu, on tente le suivant
            continue

    if not last:
        raise KeyError("Aucun arbitrage trouvé pour cette collectivité")

    # fallback ultime: normalise ce qu'on a
    return _normalize_arbitrage_doc(last)


def get_settings(collectivite_id: str) -> Dict[str, Any]:
    db = get_db()
    doc = db.collectivites_settings.find_one(
        {"collectivite_id": collectivite_id},
        projection={"_id": 0},
    )
    if not doc:
        # valeurs par défaut si rien en base
        return {
            "collectivite_id": collectivite_id,
            "poids_climat": 0.4,
            "poids_education": 0.3,
            "poids_financier": 0.3,
        }
    return doc

def get_settings(collectivite_id: str) -> Dict[str, Any]:
    db = get_db()
    doc = db.collectivites_settings.find_one(
        {"collectivite_id": collectivite_id},
        projection={"_id": 0},
    )
    if not doc:
        return {
            "collectivite_id": collectivite_id,
            "poids_climat": 0.4,
            "poids_education": 0.3,
            "poids_financier": 0.3,
        }
    return doc

def get_arbitrage_by_id(collectivite_id: str, arbitrage_id: str) -> Dict[str, Any]:
    db = get_db()
    doc = db.arbitrages.find_one(
        {
            "collectivite_id": collectivite_id,
            "arbitrage_id": arbitrage_id,
        },
        projection={"_id": 0},
    )
    if not doc:
        raise KeyError("Arbitrage introuvable")

    return _to_api_out(doc)


def list_arbitrages(collectivite_id: str, page: int = 1, limit: int = 10) -> Dict[str, Any]:
    """
    Pagination des arbitrages (engine v2 uniquement), tri du plus récent au plus ancien.
    Retourne un format compatible ArbitrageListOut.
    """
    if page < 1:
        page = 1
    if limit < 1:
        limit = 1
    if limit > 50:
        limit = 50

    db = get_db()
    filt = {"collectivite_id": collectivite_id, "engine_version": ENGINE_VERSION}

    total = db.arbitrages.count_documents(filt)
    skip = (page - 1) * limit

    cursor = (
        db.arbitrages.find(filt, projection={"_id": 0})
        .sort([("created_at_dt", -1), ("created_at", -1)])
        .skip(skip)
        .limit(limit + 1)
    )

    docs = list(cursor)
    has_next = len(docs) > limit
    docs = docs[:limit]

    items = []
    for doc in docs:
        out = _to_api_out(doc)
        items.append(
            {
                "arbitrage_id": out["arbitrage_id"],
                "collectivite_id": out["collectivite_id"],
                "mandat": out["mandat"],
                "synthese": out["synthese"],
                "audit": out["audit"],
            }
        )

    return {
        "page": page,
        "limit": limit,
        "total": int(total),
        "has_next": bool(has_next),
        "items": items,
    }
