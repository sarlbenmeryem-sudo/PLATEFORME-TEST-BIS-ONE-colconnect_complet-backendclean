from fastapi import APIRouter, HTTPException, Header
from pydantic import ValidationError

from schemas.arbitrage import ArbitrageRunIn, ArbitrageRunOut, CollectiviteSettings
from services.arbitrage_service import run_arbitrage, get_last_arbitrage, upsert_settings

router = APIRouter(prefix="/api/v1", tags=["arbitrage"])


def _err(status: int, code: str, message: str):
    raise HTTPException(status_code=status, detail={"code": code, "message": message})


@router.post("/collectivites/{collectivite_id}/arbitrage:run", response_model=ArbitrageRunOut)
def post_arbitrage_run(
    collectivite_id: str,
    payload: ArbitrageRunIn,
    x_user_id: str | None = Header(default=None, alias="X-User-Id"),
):
    triggered_by = x_user_id or "anonymous"
    try:
        data = payload.model_dump()
        out = run_arbitrage(collectivite_id, data, triggered_by=triggered_by)
        # On renvoie uniquement le contrat Out (extra forbid côté response_model)
        return {
            "arbitrage_id": out["arbitrage_id"],
            "collectivite_id": out["collectivite_id"],
            "mandat": out["mandat"],
            "synthese": out["synthese"],
            "projets": out["projets"],
            "audit": out["audit"],
        }
    except ValidationError as e:
        _err(422, "VALIDATION_ERROR", str(e))
    except RuntimeError as e:
        _err(500, "RUNTIME_ERROR", str(e))
    except Exception as e:
        _err(500, "INTERNAL_ERROR", str(e))


@router.get("/collectivites/{collectivite_id}/arbitrage:last", response_model=ArbitrageRunOut)
def get_arbitrage_last(collectivite_id: str):
    try:
        out = get_last_arbitrage(collectivite_id)
        return {
            "arbitrage_id": out["arbitrage_id"],
            "collectivite_id": out["collectivite_id"],
            "mandat": out["mandat"],
            "synthese": out["synthese"],
            "projets": out["projets"],
            "audit": out["audit"],
        }
    except KeyError as e:
        _err(404, "NOT_FOUND", str(e))
    except Exception as e:
        _err(500, "INTERNAL_ERROR", str(e))


@router.put("/collectivites/{collectivite_id}/settings", response_model=dict)
def put_collectivite_settings(collectivite_id: str, payload: CollectiviteSettings):
    try:
        doc = upsert_settings(collectivite_id, payload.model_dump())
        return {"collectivite_id": collectivite_id, "settings": doc}
    except ValidationError as e:
        _err(422, "VALIDATION_ERROR", str(e))
    except Exception as e:
        _err(500, "INTERNAL_ERROR", str(e))
