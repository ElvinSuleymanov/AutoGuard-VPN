import subprocess
import os
from fastapi import FastAPI, Security, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

bearer = HTTPBearer()

def verify(creds: HTTPAuthorizationCredentials = Security(bearer)) -> None:
    if creds.credentials != SIDECAR_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid token")
    

def wg(*args: str) -> str:
    try:
        result = subprocess.run(
            ["wg", *args],
            capture_output=True, text=True, check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        raise HTTPException(status_code=500, detail=e.stderr.strip())