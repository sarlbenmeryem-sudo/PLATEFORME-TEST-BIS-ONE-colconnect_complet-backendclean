import os, time
from jose import jwt
secret = os.environ["JWT_SECRET"]
payload = {
  "sub": "demo-user",
  "collectivites": ["paris-75000"],  # pas nova
  "scopes": ["arbitrage:read","arbitrage:write","settings:read","settings:write"],
  "exp": int(time.time()) + 3600,
}
print(jwt.encode(payload, secret, algorithm="HS256"))
