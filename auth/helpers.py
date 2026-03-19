import os
import secrets
from fastapi import HTTPException, Security
from fastapi.security import APIKeyHeader

AUTH_KEY_SCRIPT = os.environ["AUTH_KEY_SCRIPT"]
api_key_header = APIKeyHeader(name="X-Auth-Token")


def verify(key: str = Security(api_key_header)):
    if not secrets.compare_digest(key, AUTH_KEY_SCRIPT):
        raise HTTPException(status_code=401, detail="Invalid token")