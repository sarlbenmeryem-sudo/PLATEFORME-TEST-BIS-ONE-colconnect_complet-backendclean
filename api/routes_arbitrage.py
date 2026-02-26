from fastapi import APIRouter, HTTPException, Header, Query
from pydantic import ValidationError

from schemas.arbitrage import (
    ArbitrageRunIn,
    ArbitrageRunOut,
    CollectiviteSettings,
    ArbitrageListOut,
    ArbitrageCursorOut,
)
from services.arbitrage_service import (
    run_arbitrage,
    get_last_arbitrage_out,
    upsert_settings,
    get_settings,
    get_arbitrage_by_id,
    list_arbitrages,
    list_arbitrages_cursor,
)

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
    except Exception as e:
        _err(500, "INTERNAL_ERROR", str(e))


@router.get("/collectivites/{collectivite_id}/arbitrage:last", response_model=ArbitrageRunOut)
def get_arbitrage_last(collectivite_id: str):
    try:
        return get_last_arbitrage_out(collectivite_id)
    except KeyError as e:
        _err(404, "NOT_FOUND", str(e))
    except Exception as e:
        _err(500, "INTERNAL_ERROR", str(e))


@router.get("/collectivites/{collectivite_id}/arbitrage/{arbitrage_id}", response_model=ArbitrageRunOut)
def get_arbitrage_by_id_route(collectivite_id: str, arbitrage_id: str):
    try:
        return get_arbitrage_by_id(collectivite_id, arbitrage_id)
    except KeyError as e:
        _err(404, "NOT_FOUND", str(e))
    except Exception as e:
        _err(500, "INTERNAL_ERROR", str(e))


@router.get("/collectivites/{collectivite_id}/arbitrages", response_model=ArbitrageListOut)
def get_arbitrages_paginated(
    collectivite_id: str,
    page: int = Query(default=1, ge=1),
    limit: int = Query(default=10, ge=1, le=50),
):
    try:
        return list_arbitrages(collectivite_id, page=page, limit=limit)
    except Exception as e:
        _err(500, "INTERNAL_ERROR", str(e))


@router.get("/collectivites/{collectivite_id}/arbitrages-cursor", response_model=ArbitrageCursorOut)
def get_arbitrages_cursor(
    collectivite_id: str,
    limit: int = Query(default=10, ge=1, le=50),
    cursor: str | None = Query(default=None),
):
    try:
        return list_arbitrages_cursor(collectivite_id, limit=limit, cursor=cursor)
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


@router.get("/collectivites/{collectivite_id}/settings", response_model=dict)
def get_collectivite_settings(collectivite_id: str):
    try:
        return {"collectivite_id": collectivite_id, "settings": get_settings(collectivite_id)}
    except Exception as e:
        _err(500, "INTERNAL_ERROR", str(e))
