from __future__ import annotations

from typing import List, Literal, Optional, Dict, Any
from pydantic import BaseModel, ConfigDict, Field


# ---------- INPUT ----------
class Contraintes(BaseModel):
    model_config = ConfigDict(extra="forbid")
    budget_investissement_max: float = Field(..., ge=0)
    seuil_capacite_desendettement_ans: float = Field(..., ge=0)


class Hypotheses(BaseModel):
    model_config = ConfigDict(extra="forbid")
    taux_subventions_moyen: float = Field(..., ge=0, le=1)
    inflation_travaux: float = Field(..., ge=-0.5, le=2)  # borne large
    annee_reference: int = Field(..., ge=2000, le=2100)
    epargne_brute_annuelle: float
    encours_dette_initial: float = Field(..., ge=0)


class ProjetIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    id: str
    nom: str
    cout_ttc: float = Field(..., ge=0)
    priorite: Literal["elevee", "moyenne", "faible"]
    impact_climat: Literal["fort", "moyen", "faible"]
    impact_education: Literal["fort", "moyen", "faible"]
    annee_realisation: int = Field(..., ge=2000, le=2100)


class ArbitrageRunIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    mandat: str
    contraintes: Contraintes
    hypotheses: Hypotheses
    projets: List[ProjetIn] = Field(default_factory=list)


# ---------- SETTINGS (DB) ----------
class CollectiviteSettings(BaseModel):
    """
    Pondérations dynamiques pilotant le scoring.
    """
    model_config = ConfigDict(extra="forbid")
    poids_climat: float = Field(0.4, ge=0, le=1)
    poids_education: float = Field(0.3, ge=0, le=1)
    poids_financier: float = Field(0.3, ge=0, le=1)


# ---------- OUTPUT ----------
class ProjetOut(BaseModel):
    model_config = ConfigDict(extra="forbid")
    id: str
    nom: str
    cout_ttc: float
    annee_realisation: int
    score: float
    retenu: bool
    details_score: Dict[str, Any] = Field(default_factory=dict)


class ArbitrageSynthese(BaseModel):
    model_config = ConfigDict(extra="forbid")
    budget_max: float
    budget_retenu: float
    budget_restant: float
    nb_projets_total: int
    nb_projets_retenus: int


class AuditTrail(BaseModel):
    model_config = ConfigDict(extra="forbid")
    engine_version: str
    triggered_by: str
    payload_hash: str
    timestamp_utc: str  # isoformat


class ArbitrageRunOut(BaseModel):
    model_config = ConfigDict(extra="forbid")
    arbitrage_id: str
    collectivite_id: str
    mandat: str
    synthese: ArbitrageSynthese
    projets: List[ProjetOut]
    audit: AuditTrail
