from datetime import datetime

def compute_score(projet):
    scoring = projet.get("scoring", {})
    return (
        scoring.get("impact_service_public", 0) * 0.4 +
        scoring.get("impact_transition", 0) * 0.3 +
        scoring.get("urgence", 0) * 0.2 -
        scoring.get("risque_financier", 0) * 0.1
    )

def decide(score):
    if score >= 70:
        return "KEEP"
    elif score >= 40:
        return "DEFER"
    return "DROP"

def run_engine(db, collectivite_id, payload):
    projets = list(db.projets.find({"collectivite_id": collectivite_id}, {"_id": 0}))
    budget_max = payload.get("contraintes", {}).get("budget_investissement_max", 0)

    total_keep_budget = 0
    results = []

    for p in projets:
        score = compute_score(p)
        decision = decide(score)

        cout = p.get("ppi", {}).get("cout_total_ttc", 0)

        if decision == "KEEP":
            if total_keep_budget + cout > budget_max:
                decision = "DEFER"
            else:
                total_keep_budget += cout

        results.append({
            "collectivite_id": collectivite_id,
            "projet_nom": p.get("nom"),
            "score": score,
            "decision": decision,
            "cout": cout
        })

    if results:
        db.arbitrage_projects.insert_many(results)

    synthese = {
        "nb_projets_total": len(results),
        "nb_keep": len([r for r in results if r["decision"] == "KEEP"]),
        "nb_defer": len([r for r in results if r["decision"] == "DEFER"]),
        "nb_drop": len([r for r in results if r["decision"] == "DROP"]),
        "budget_keep_total": total_keep_budget
    }

    return results, synthese
