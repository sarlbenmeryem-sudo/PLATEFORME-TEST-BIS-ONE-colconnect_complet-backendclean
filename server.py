from fastapi import FastAPI
from motor.motor_asyncio import AsyncIOMotorClient
import os

# ---------------------------------------------------------
# INITIALISATION FASTAPI
# ---------------------------------------------------------
app = FastAPI()

# ---------------------------------------------------------
# CONNEXION MONGODB
# ---------------------------------------------------------
MONGO_URL = os.getenv("MONGO_URL")
DB_NAME = os.getenv("DB_NAME")

client = AsyncIOMotorClient(MONGO_URL)
db = client[DB_NAME]

# ---------------------------------------------------------
# ENDPOINT DE TEST MONGO
# ---------------------------------------------------------
@app.get("/api/test-mongo")
async def test_mongo():
    try:
        await db.command("ping")
        return {"status": "ok", "mongo": "connected"}
    except Exception as e:
        return {"status": "error", "mongo": str(e)}

# ---------------------------------------------------------
# (Tes autres endpoints peuvent rester en dessous)
# ---------------------------------------------------------
