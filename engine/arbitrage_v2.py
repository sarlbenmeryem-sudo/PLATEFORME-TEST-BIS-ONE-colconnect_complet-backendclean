from __future__ import annotations

from typing import Any, Dict, List


ENGINE_VERSION = "2.0.0"


def _map_level(level: str) -> float:
    # Normalise vers [0, 1]
    return {"faible": 0.2, "moyen": 0.6, "fort": 1.0}.get(level, 0.0)


def _map_priorite(p: str) -> float:
    return {"faible": 0.2, "moyenne": 0.6, "elevee": 1.0}.get(p, 0.0)


def calculer_arbitrage_2_0(payload: Dict[str, Any], weights: Dict[str, float]) -> Dict[str, Any]:
    """
    Calcul pur (sans FastAPI/Mongo).
    payload: dict (mandat, contraintes, hypotheses, projets...)
    weights: {"poids_climat":..., "poids_education":..., "poids_financier":...}
    """
    contraintes = payload["contraintes"]
    budget_max = float(contraintes["budget_investissement_max"])

    w_climat = float(weights.get("poids_climat", 0.4))
    w_edu = float(weights.get("poids_education", 0.3))
    w_fin = float(weights.get("poids_financier", 0.3))

    projets_in: List[Dict[str, Any]] = list(payload.get("projets", []))

    scored: List[Dict[str, Any]] = []
    for p in projets_in:
        cout = float(p["cout_ttc"])

        score_climat = _map_level(p["impact_climat"])
        score_edu = _map_level(p["impact_education"])
        score_prio = _map_priorite(p["priorite"])

        # Score financier simple (plus c'est cher, moins bon), borné
        # (évite les divisions par 0)
        score_fin = 1.0 / (1.0 + (cout / max(budget_max, 1.0)))

        score = (
            w_climat * score_climat
            + w_edu * score_edu
            + w_fin * (0.6 * score_fin + 0.4 * score_prio)
        )

        scored.append(
            {
                "id": p["id"],
                "nom": p["nom"],
                "cout_ttc": cout,
                "annee_realisation": int(p["annee_realisation"]),
                "score": float(round(score, 6)),
                "details_score": {
                    "score_climat": score_climat,
                    "score_education": score_edu,
                    "score_financier": score_fin,
                    "score_priorite": score_prio,
                    "poids": {"climat": w_climat, "education": w_edu, "financier": w_fin},
                },
            }
        )

    # Tri score desc, puis coût asc
    scored.sort(key=lambda x: (-x["score"], x["cout_ttc"]))

    budget_retenu = 0.0
    projets_out: List[Dict[str, Any]] = []
    for p in scored:
        if budget_retenu + p["cout_ttc"] <= budget_max:
            retenu = True
            budget_retenu += p["cout_ttc"]
        else:
            retenu = False
        projets_out.append({**p, "retenu": retenu})

    synthese = {
        "budget_max": float(round(budget_max, 2)),
        "budget_retenu": float(round(budget_retenu, 2)),
        "budget_restant": float(round(budget_max - budget_retenu, 2)),
        "nb_projets_total": len(projets_out),
        "nb_projets_retenus": sum(1 for p in projets_out if p["retenu"]),
    }

    return {
        "mandat": payload["mandat"],
        "synthese": synthese,
        "projets": projets_out,
        "engine_version": ENGINE_VERSION,
    }
