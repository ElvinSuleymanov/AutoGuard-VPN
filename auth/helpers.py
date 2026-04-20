import os
import secrets
import base64
import re
from fastapi import HTTPException, Security
from fastapi.security import APIKeyHeader



REGISTRATION_TOKEN = os.environ["REGISTRATION_TOKEN"]
api_key_header = APIKeyHeader(name="X-Auth-Token")


def verify(key: str = Security(api_key_header)) -> None:
    if not secrets.compare_digest(key, REGISTRATION_TOKEN):
        raise HTTPException(status_code=401, detail="Invalid token")
    

def is_valid_wg_pubkey(key: str) -> bool:
    if not re.fullmatch(r'[A-Za-z0-9+/]{43}=', key):
        return False
    try:
        decoded = base64.b64decode(key)
        return len(decoded) == 32 
    except Exception:
        return False