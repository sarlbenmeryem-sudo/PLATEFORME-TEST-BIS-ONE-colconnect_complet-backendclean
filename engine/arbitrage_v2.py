from datetime import datetime
from copy import deepcopy

PRIORITE_MAP = {"elevee": 3, "moyenne": 2, "faible": 1}
IMPACT_MAP = {"fort": 2, "moyen": 1, "faible": 0}

def scorer_projet(p):
    wp, wc, we = 0.4, 0.3, 0.3

    priorite = PRIORITE_MAP.get(p.get("priorite"), 1)
    impact_climat = IMPACT_MAP.get(p.get("impact_climat"), 0)
    impact_education = IMPACT_MAP.get(p.get("impact_education"), 0)

    score_brut = (
        wp * priorite +
        wc * impact_climat +
        we * impact_education
    )

    # normalisation sur 0-1
    return min(1.0, score_brut / 3.0)

def calculer_arbitrage_2_0(payload: dict) -> dict:
    data = deepcopy(payload)

    projets = data["projets"]
    contraintes = data["contraintes"]
    hyp = data["hypotheses"]

    # 1️⃣ Scoring
    for p in projets:
        p["score"] = scorer_projet(p)

    # 2️⃣ Décision initiale
    for p in projets:
        if p["score"] >= 0.7:
            p["decision"] = "keep"
        elif p["score"] >= 0.4:
            p["decision"] = "defer"
        else:
            p["decision"] = "drop"

    # 3️⃣ Totaux initiaux
    cout_total_initial = sum(p["cout_ttc"] for p in projets)
    cout_retenu = sum(
        p["cout_ttc"]
        for p in projets
        if p["decision"] in ["keep", "defer"]
    )

    # 4️⃣ Ajustement budget
    if cout_retenu > contraintes["budget_investissement_max"]:
        retenus = sorted(
            [p for p in projets if p["decision"] in ["keep", "defer"]],
            key=lambda x: x["score"]
        )
        for p in retenus:
            if cout_retenu <= contraintes["budget_investissement_max"]:
                break
            p["decision"] = "drop"
            cout_retenu -= p["cout_ttc"]

    # 5️⃣ Capacité de désendettement
    encours_initial = hyp["encours_dette_initial"]
    epargne = hyp["epargne_brute_annuelle"]
    taux_subv = hyp["taux_subventions_moyen"]

    cd_initial = encours_initial / epargne
    encours_proj = encours_initial + cout_retenu * (1 - taux_subv)
    cd_proj = encours_proj / epargne

    respect_seuil = cd_proj <= contraintes["seuil_capacite_desendettement_ans"]

    # 6️⃣ Synthèse
    synthese = {
        "nb_projets_total": len(projets),
        "nb_keep": sum(1 for p in projets if p["decision"] == "keep"),
        "nb_defer": sum(1 for p in projets if p["decision"] == "defer"),
        "nb_drop": sum(1 for p in projets if p["decision"] == "drop"),
        "investissement_mandat": {
            "cout_total_ttc_initial": cout_total_initial,
            "cout_total_ttc_retenu": cout_retenu,
            "economies_realisees": cout_total_initial - cout_retenu
        },
        "impact_capacite_desendettement": {
            "capacite_initiale_annees": cd_initial,
            "capacite_proj_annees": cd_proj,
            "respect_seuil": respect_seuil
        }
    }

    data["synthese"] = synthese
    data["status"] = {
        "state": "done",
        "score_global": min(
            1.0,
            max(0.0, 1 - (cd_proj / contraintes["seuil_capacite_desendettement_ans"]))
        ),
        "respect_contraintes": respect_seuil
    }

    return data
