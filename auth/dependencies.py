import os
from typing import Any, Dict, List

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt

security = HTTPBearer(auto_error=True)

JWT_SECRET = os.getenv("JWT_SECRET", "dev-secret")
JWT_ALGO = os.getenv("JWT_ALGO", "HS256")


def _http_error(code: int, msg: str):
    raise HTTPException(
        status_code=code,
        detail={"code": "AUTH_ERROR" if code == 401 else "FORBIDDEN", "message": msg},
    )


def get_current_user(
    creds: HTTPAuthorizationCredentials = Depends(security),
) -> Dict[str, Any]:
    token = creds.credentials
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGO])
    except JWTError:
        _http_error(status.HTTP_401_UNAUTHORIZED, "Invalid token")

    # Champs attendus (tolérance: collectivites/scopes peuvent être absents -> liste vide)
    sub = payload.get("sub")
    if not sub:
        _http_error(status.HTTP_401_UNAUTHORIZED, "Token missing 'sub'")

    payload.setdefault("collectivites", [])
    payload.setdefault("scopes", [])
    return payload


def require_collectivite_access(
    collectivite_id: str,
    user: Dict[str, Any] = Depends(get_current_user),
) -> Dict[str, Any]:
    allowed: List[str] = user.get("collectivites") or []
    if collectivite_id not in allowed:
        _http_error(status.HTTP_403_FORBIDDEN, "Forbidden for this collectivite")
    return user


def require_scope(scope: str):
    def _checker(user: Dict[str, Any] = Depends(get_current_user)) -> Dict[str, Any]:
        scopes: List[str] = user.get("scopes") or []
        if scope not in scopes:
            _http_error(status.HTTP_403_FORBIDDEN, f"Missing scope: {scope}")
        return user

    return _checker
