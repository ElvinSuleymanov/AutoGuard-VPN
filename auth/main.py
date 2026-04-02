import os
import requests;
from fastapi import FastAPI, Security
from helpers import verify, is_valid_wg_pubkey
from pydantic import BaseModel, validator
from fastapi import HTTPException



#Variables
app = FastAPI()
ip_sidecar = os.environ["IP_SIDECAR"]
port_sidecar = os.environ["PORT_SIDECAR"]

#Models
class PeerRequest(BaseModel):
    public_key:str
    @validator("public_key")
    def validate_public_key(cls, v):
        if not is_valid_wg_pubkey(v):
            raise ValueError("Invalid WireGuard public key")
        return v
    
#Routes
@app.get("/health")
def health_check():
    try:
        return {"status":"ok"}
    except:
        return {"status":"auth service is not ready"}

@app.get("/addnewpeer", dependencies=[Security(verify)])
def add_peer(peer: PeerRequest):
    response = requests.post(  
        f"http://{ip_sidecar}:{port_sidecar}/pubkey"
        ,{"client_pub":peer.public_key}
    )
    return response.json()