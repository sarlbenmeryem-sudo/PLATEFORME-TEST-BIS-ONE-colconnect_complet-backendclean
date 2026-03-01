import asyncio
from motor.motor_asyncio import AsyncIOMotorClient
import os

MONGO_URI = os.getenv("MONGO_URI")
DB_NAME = os.getenv("DB_NAME", "colconnect")

async def main():
    client = AsyncIOMotorClient(MONGO_URI)
    db = client[DB_NAME]
    await db.collectivites.create_index("nom")
    print("Index created on 'nom'")

asyncio.run(main())
