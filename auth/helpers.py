import os
import secrets
from fastapi import HTTPException, Security
from fastapi.security import APIKeyHeader

REGISTRATION_TOKEN = os.environ["REGISTRATION_TOKEN"]
api_key_header = APIKeyHeader(name="X-Auth-Token")


def verify(key: str = Security(api_key_header)):
    if not secrets.compare_digest(key, REGISTRATION_TOKEN):
        raise HTTPException(status_code=401, detail="Invalid token")