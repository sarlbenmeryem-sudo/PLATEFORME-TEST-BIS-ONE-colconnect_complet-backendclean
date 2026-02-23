from fastapi import FastAPI, APIRouter, HTTPException
from dotenv import load_dotenv
from starlette.middleware.cors import CORSMiddleware
from motor.motor_asyncio import AsyncIOMotorClient
import os
import logging
from pathlib import Path
from pydantic import BaseModel, Field, ConfigDict
from typing import List, Optional, Literal
import uuid
from datetime import datetime, timezone


ROOT_DIR = Path(__file__).parent
load_dotenv(ROOT_DIR / '.env')

# MongoDB connection
mongo_url = os.environ['MONGO_URL']
client = AsyncIOMotorClient(mongo_url)
db = client[os.environ['DB_NAME']]

# Create the main app without a prefix
app = FastAPI()

# Create a router with the /api prefix
api_router = APIRouter(prefix="/api")


# Define Models
class StatusCheck(BaseModel):
    model_config = ConfigDict(extra="ignore")
    
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    client_name: str
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


# ==========================================
# ARBITRAGE MODELS
# ==========================================

Decision = Literal["KEEP", "DEFER", "DROP"]

class ArbitrageProject(BaseModel):
    model_config = ConfigDict(extra="ignore")
    
    id: str = Field(default_factory=lambda: f"p_{uuid.uuid4().hex[:8]}")
    name: str
    tag: str = ""
    costME: float = 0.0
    impact: int = Field(default=50, ge=0, le=100)
    urgence: int = Field(default=50, ge=0, le=100)
    risk: int = Field(default=30, ge=0, le=100)
    cap: int = Field(default=2, ge=1, le=5)
    eligible: bool = True
    decision: Decision = "DEFER"
    score: float = 0.0

class ArbitrageProjectCreate(BaseModel):
    name: str
    tag: str = ""
    costME: float = 0.0
    impact: int = Field(default=50, ge=0, le=100)
    urgence: int = Field(default=50, ge=0, le=100)
    risk: int = Field(default=30, ge=0, le=100)
    cap: int = Field(default=2, ge=1, le=5)
    eligible: bool = True

class ArbitrageProjectUpdate(BaseModel):
    name: Optional[str] = None
    tag: Optional[str] = None
    costME: Optional[float] = None
    impact: Optional[int] = None
    urgence: Optional[int] = None
    risk: Optional[int] = None
    cap: Optional[int] = None
    eligible: Optional[bool] = None
    decision: Optional[Decision] = None

class ArbitrageParams(BaseModel):
    budgetTotal: float = 30.0
    capMax: int = 8
    riskMax: int = 75
    wImpact: int = 45
    wUrgence: int = 35
    wRisque: int = 20

class ArbitrageStatus(BaseModel):
    status: str = "warning"
    decision: str = "Arbitrage indisponible"
    pourquoi: str = "Données en cours de chargement..."
    actions: List[str] = []
    impact: str = "-"
    urgence: str = "-"
    horizon: str = "7 jours"
    projectsCount: int = 0
    keepCount: int = 0
    budgetUsed: float = 0.0
    budgetTotal: float = 30.0

class ArbitrageFullState(BaseModel):
    params: ArbitrageParams
    projects: List[ArbitrageProject]
    status: ArbitrageStatus

class StatusCheckCreate(BaseModel):
    client_name: str

# Add your routes to the router instead of directly to app
@api_router.get("/")
async def root():
    return {"message": "Hello World"}

@api_router.post("/status", response_model=StatusCheck)
async def create_status_check(input: StatusCheckCreate):
    status_dict = input.model_dump()
    status_obj = StatusCheck(**status_dict)
    
    # Convert to dict and serialize datetime to ISO string for MongoDB
    doc = status_obj.model_dump()
    doc['timestamp'] = doc['timestamp'].isoformat()
    
    _ = await db.status_checks.insert_one(doc)
    return status_obj

@api_router.get("/status", response_model=List[StatusCheck])
async def get_status_checks():
    # Exclude MongoDB's _id field from the query results
    status_checks = await db.status_checks.find({}, {"_id": 0}).to_list(1000)
    
    # Convert ISO string timestamps back to datetime objects
    for check in status_checks:
        if isinstance(check['timestamp'], str):
            check['timestamp'] = datetime.fromisoformat(check['timestamp'])
    
    return status_checks


# ==========================================
# ARBITRAGE API ENDPOINTS
# ==========================================

def calculate_score(project: dict, params: dict) -> float:
    """Calculate project score based on weighted factors"""
    wi = params.get('wImpact', 45) / 100
    wu = params.get('wUrgence', 35) / 100
    wr = params.get('wRisque', 20) / 100
    
    score = (project['impact'] * wi) + (project['urgence'] * wu) - (project['risk'] * wr)
    return round(score, 1)

def compute_arbitrage_status(projects: List[dict], params: dict) -> dict:
    """Compute the arbitrage banner status from projects"""
    keep_projects = [p for p in projects if p.get('decision') == 'KEEP']
    defer_projects = [p for p in projects if p.get('decision') == 'DEFER']
    drop_projects = [p for p in projects if p.get('decision') == 'DROP']
    
    budget_used = sum(p.get('costME', 0) for p in keep_projects)
    budget_total = params.get('budgetTotal', 30)
    cap_used = sum(p.get('cap', 0) for p in keep_projects)
    cap_max = params.get('capMax', 8)
    
    # Determine status
    if len(keep_projects) == 0:
        status = "warning"
        decision = "Aucun projet arbitré"
        pourquoi = "Lancez l'arbitrage automatique ou décidez manuellement."
        actions = ["Lancer l'arbitrage automatique", "Revoir les paramètres", "Ajouter des projets"]
        impact_level = "-"
        urgence_level = "-"
    elif budget_used > budget_total * 0.9:
        status = "error"
        decision = f"Budget critique ({budget_used:.1f}M€ / {budget_total:.1f}M€)"
        pourquoi = "Le budget engagé approche la limite. Arbitrage nécessaire."
        actions = ["Revoir les projets gardés", "Augmenter le budget", "Reporter certains projets"]
        impact_level = "Élevé"
        urgence_level = "Haute"
    elif cap_used > cap_max * 0.8:
        status = "warning"
        decision = f"Capacité sous tension ({cap_used}/{cap_max})"
        pourquoi = "La capacité chantier est presque saturée."
        actions = ["Vérifier les ressources", "Échelonner les travaux", "Reporter si nécessaire"]
        impact_level = "Moyen"
        urgence_level = "Moyenne"
    else:
        status = "ok"
        decision = f"{len(keep_projects)} projet(s) gardé(s)"
        pourquoi = f"Budget: {budget_used:.1f}M€/{budget_total:.1f}M€ • Capacité: {cap_used}/{cap_max}"
        actions = ["Valider le portefeuille", "Exporter le rapport", "Suivre l'avancement"]
        impact_level = "Faible"
        urgence_level = "Basse"
    
    # Calculate average risk for kept projects
    avg_risk = sum(p.get('risk', 0) for p in keep_projects) / len(keep_projects) if keep_projects else 0
    horizon = "7 jours" if avg_risk < 50 else "3 jours" if avg_risk < 75 else "Immédiat"
    
    return {
        "status": status,
        "decision": decision,
        "pourquoi": pourquoi,
        "actions": actions,
        "impact": impact_level,
        "urgence": urgence_level,
        "horizon": horizon,
        "projectsCount": len(projects),
        "keepCount": len(keep_projects),
        "budgetUsed": budget_used,
        "budgetTotal": budget_total
    }

async def get_or_create_arbitrage_params() -> dict:
    """Get or create default arbitrage parameters"""
    params = await db.arbitrage_params.find_one({}, {"_id": 0})
    if not params:
        params = ArbitrageParams().model_dump()
        await db.arbitrage_params.insert_one(params)
    return params

async def seed_default_projects():
    """Seed default projects if none exist"""
    count = await db.arbitrage_projects.count_documents({})
    if count == 0:
        default_projects = [
            {"id": f"p_{uuid.uuid4().hex[:8]}", "name": "Rénovation école Jaurès", "tag": "Éducation", "costME": 5.2, "impact": 86, "urgence": 72, "risk": 35, "cap": 3, "eligible": True, "decision": "DEFER", "score": 0},
            {"id": f"p_{uuid.uuid4().hex[:8]}", "name": "Requalification Avenue République", "tag": "Voirie", "costME": 7.4, "impact": 74, "urgence": 60, "risk": 55, "cap": 4, "eligible": True, "decision": "DEFER", "score": 0},
            {"id": f"p_{uuid.uuid4().hex[:8]}", "name": "Station de pompage – sécurisation", "tag": "Eau", "costME": 3.1, "impact": 82, "urgence": 88, "risk": 62, "cap": 2, "eligible": True, "decision": "DEFER", "score": 0},
            {"id": f"p_{uuid.uuid4().hex[:8]}", "name": "Médiathèque – extension", "tag": "Culture", "costME": 4.6, "impact": 58, "urgence": 35, "risk": 40, "cap": 2, "eligible": True, "decision": "DEFER", "score": 0},
            {"id": f"p_{uuid.uuid4().hex[:8]}", "name": "Centre sportif – toiture", "tag": "Sport", "costME": 2.9, "impact": 63, "urgence": 52, "risk": 30, "cap": 2, "eligible": True, "decision": "DEFER", "score": 0},
            {"id": f"p_{uuid.uuid4().hex[:8]}", "name": "LED + télégestion éclairage", "tag": "Énergie", "costME": 6.8, "impact": 70, "urgence": 66, "risk": 48, "cap": 3, "eligible": True, "decision": "DEFER", "score": 0},
            {"id": f"p_{uuid.uuid4().hex[:8]}", "name": "Déploiement capteurs qualité air", "tag": "SmartCity", "costME": 1.2, "impact": 49, "urgence": 40, "risk": 22, "cap": 1, "eligible": True, "decision": "DEFER", "score": 0},
            {"id": f"p_{uuid.uuid4().hex[:8]}", "name": "Restructuration bâtiment mairie", "tag": "Patrimoine", "costME": 9.1, "impact": 76, "urgence": 58, "risk": 78, "cap": 5, "eligible": True, "decision": "DEFER", "score": 0},
            {"id": f"p_{uuid.uuid4().hex[:8]}", "name": "Tranche 2 – Réseau assainissement", "tag": "Eau", "costME": 8.9, "impact": 80, "urgence": 74, "risk": 69, "cap": 4, "eligible": True, "decision": "DEFER", "score": 0},
        ]
        await db.arbitrage_projects.insert_many(default_projects)
        logger.info("Seeded default arbitrage projects")

@api_router.get("/arbitrage/status", response_model=ArbitrageStatus)
async def get_arbitrage_status():
    """Get the arbitrage banner status"""
    await seed_default_projects()
    params = await get_or_create_arbitrage_params()
    projects = await db.arbitrage_projects.find({}, {"_id": 0}).to_list(1000)
    
    # Recalculate scores
    for p in projects:
        p['score'] = calculate_score(p, params)
    
    status = compute_arbitrage_status(projects, params)
    return ArbitrageStatus(**status)

@api_router.get("/arbitrage/projects", response_model=List[ArbitrageProject])
async def get_arbitrage_projects():
    """Get all arbitrage projects"""
    await seed_default_projects()
    params = await get_or_create_arbitrage_params()
    projects = await db.arbitrage_projects.find({}, {"_id": 0}).to_list(1000)
    
    # Recalculate scores
    for p in projects:
        p['score'] = calculate_score(p, params)
    
    return [ArbitrageProject(**p) for p in projects]

@api_router.post("/arbitrage/projects", response_model=ArbitrageProject)
async def create_arbitrage_project(project: ArbitrageProjectCreate):
    """Create a new arbitrage project"""
    params = await get_or_create_arbitrage_params()
    
    project_dict = project.model_dump()
    project_dict['id'] = f"p_{uuid.uuid4().hex[:8]}"
    project_dict['decision'] = "DEFER"
    project_dict['score'] = calculate_score(project_dict, params)
    
    await db.arbitrage_projects.insert_one(project_dict)
    return ArbitrageProject(**project_dict)

@api_router.put("/arbitrage/projects/{project_id}", response_model=ArbitrageProject)
async def update_arbitrage_project(project_id: str, update: ArbitrageProjectUpdate):
    """Update an arbitrage project"""
    params = await get_or_create_arbitrage_params()
    
    existing = await db.arbitrage_projects.find_one({"id": project_id}, {"_id": 0})
    if not existing:
        raise HTTPException(status_code=404, detail="Project not found")
    
    update_data = {k: v for k, v in update.model_dump().items() if v is not None}
    if update_data:
        existing.update(update_data)
        existing['score'] = calculate_score(existing, params)
        await db.arbitrage_projects.update_one({"id": project_id}, {"$set": existing})
    
    return ArbitrageProject(**existing)

@api_router.delete("/arbitrage/projects/{project_id}")
async def delete_arbitrage_project(project_id: str):
    """Delete an arbitrage project"""
    result = await db.arbitrage_projects.delete_one({"id": project_id})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Project not found")
    return {"message": "Project deleted"}

@api_router.get("/arbitrage/params", response_model=ArbitrageParams)
async def get_arbitrage_params():
    """Get arbitrage parameters"""
    params = await get_or_create_arbitrage_params()
    return ArbitrageParams(**params)

@api_router.put("/arbitrage/params", response_model=ArbitrageParams)
async def update_arbitrage_params(params: ArbitrageParams):
    """Update arbitrage parameters"""
    params_dict = params.model_dump()
    await db.arbitrage_params.update_one({}, {"$set": params_dict}, upsert=True)
    return params

@api_router.post("/arbitrage/auto")
async def run_auto_arbitrage():
    """Run automatic arbitrage algorithm"""
    params = await get_or_create_arbitrage_params()
    projects = await db.arbitrage_projects.find({}, {"_id": 0}).to_list(1000)
    
    # Recalculate scores
    for p in projects:
        p['score'] = calculate_score(p, params)
    
    # Reset all decisions
    for p in projects:
        p['decision'] = "DEFER"
    
    # Sort by score descending
    ranked = sorted(projects, key=lambda x: x['score'], reverse=True)
    
    budget_total = params.get('budgetTotal', 30)
    cap_max = params.get('capMax', 8)
    risk_max = params.get('riskMax', 75)
    
    spent = 0
    cap_used = 0
    
    for p in ranked:
        if not p.get('eligible', True):
            p['decision'] = "DROP"
            continue
        
        if p.get('risk', 0) > risk_max:
            p['decision'] = "DEFER"
            continue
        
        ok_budget = (spent + p.get('costME', 0)) <= budget_total
        ok_cap = (cap_used + p.get('cap', 0)) <= cap_max
        
        if ok_budget and ok_cap:
            p['decision'] = "KEEP"
            spent += p.get('costME', 0)
            cap_used += p.get('cap', 0)
        else:
            too_tight = not ok_budget and budget_total > 0 and p.get('costME', 0) > (budget_total * 0.35)
            p['decision'] = "DROP" if too_tight else "DEFER"
    
    # Update all projects in DB
    for p in ranked:
        await db.arbitrage_projects.update_one(
            {"id": p['id']},
            {"$set": {"decision": p['decision'], "score": p['score']}}
        )
    
    status = compute_arbitrage_status(ranked, params)
    return {
        "message": "Arbitrage automatique terminé",
        "status": status,
        "projects": ranked
    }

@api_router.post("/arbitrage/reset")
async def reset_arbitrage():
    """Reset arbitrage to default state"""
    await db.arbitrage_projects.delete_many({})
    await db.arbitrage_params.delete_many({})
    await seed_default_projects()
    params = await get_or_create_arbitrage_params()
    return {"message": "Arbitrage réinitialisé"}

@api_router.get("/arbitrage/full", response_model=ArbitrageFullState)
async def get_full_arbitrage_state():
    """Get full arbitrage state (params, projects, status)"""
    await seed_default_projects()
    params = await get_or_create_arbitrage_params()
    projects = await db.arbitrage_projects.find({}, {"_id": 0}).to_list(1000)
    
    # Recalculate scores
    for p in projects:
        p['score'] = calculate_score(p, params)
    
    status = compute_arbitrage_status(projects, params)
    
    return ArbitrageFullState(
        params=ArbitrageParams(**params),
        projects=[ArbitrageProject(**p) for p in projects],
        status=ArbitrageStatus(**status)
    )

# Include the router in the main app
app.include_router(api_router)

app.add_middleware(
    CORSMiddleware,
    allow_credentials=True,
    allow_origins=os.environ.get('CORS_ORIGINS', '*').split(','),
    allow_methods=["*"],
    allow_headers=["*"],
)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@app.on_event("shutdown")
async def shutdown_db_client():
    client.close()