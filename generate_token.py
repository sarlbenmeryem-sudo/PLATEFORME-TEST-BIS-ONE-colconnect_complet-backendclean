import os
import time
from jose import jwt

secret = os.environ["JWT_SECRET"]

payload = {
    "sub": "demo-user",
    "collectivites": ["nova-sur-marne-94000"],
    "scopes": [
        "arbitrage:read",
        "arbitrage:write",
        "settings:read",
        "settings:write",
    ],
    "exp": int(time.time()) + 3600,
}

token = jwt.encode(payload, secret, algorithm="HS256")
print(token)
