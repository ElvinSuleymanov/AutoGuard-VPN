import os
import subprocess
from fastapi import FastAPI, Security
from helpers import verify, wg
from pydantic import BaseModel


app = FastAPI()

WG_INTERFACE  = os.environ.get("WG_INTERFACE", "wg0")

class PeerAdd(BaseModel):
    public_key: str

@app.get("/health")
def health_check() -> dict[str, str]:
    try:
        subprocess.run(["wg show wg0"], check=True, capture_output=True)
        return {"status":"ok"}
    except:
        return {"status":"wg0 is not ready"}
    
@app.get("/pubkey", dependencies=[Security(verify)]) 
def get_pubkey() -> dict[str, str]:
    return {"public_key": wg("show", WG_INTERFACE, "public-key")}


@app.get("/peers", dependencies=[Security(verify)])
def list_peers() -> dict[str, list[dict[str, str | int | None]]]:
    """
    `wg show wg0 dump` columns:
    public-key  preshared-key  endpoint  allowed-ips  latest-handshake  rx  tx  persistent-keepalive
    First line is the server itself — skip it.
    """
    raw = wg("show", WG_INTERFACE, "dump")
    lines = raw.splitlines()[1:]        
    peers = []
    for line in lines:
        if not line:
            continue
        parts = line.split("\t")
        peers.append({
            "public_key":        parts[0],
            "endpoint":          parts[2] if parts[2] != "(none)" else None,
            "allowed_ips":       parts[3],
            "latest_handshake":  int(parts[4]),
        })
    return {"peers": peers}


@app.post("/peers", status_code=201, dependencies=[Security(verify)])
def add_peer(peer: PeerAdd) -> dict[str, str]:
    # allowed = f"{peer.allowed_ip}/32"
    allowed = "0.0.0.0/0" #Temporarily
    wg("set", WG_INTERFACE, "peer", peer.public_key, "allowed-ips", allowed)
    return {"public_key": peer.public_key, "allowed_ip": allowed}


@app.delete("/peers/{public_key}", status_code=204, dependencies=[Security(verify)])
def remove_peer(public_key: str) -> None:
    wg("set", WG_INTERFACE, "peer", public_key, "remove")


