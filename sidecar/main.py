import os
from fastapi import FastAPI, Security
from models import PeerAdd

app = FastAPI()


SIDECAR_TOKEN = os.environ["SIDECAR_TOKEN"]
WG_INTERFACE  = os.environ.get("WG_INTERFACE", "wg0")


@app.get("/pubkey", dependencies=[Security(verify)])
def get_pubkey():
    return {"public_key": wg("show", WG_INTERFACE, "public-key")}


@app.get("/peers", dependencies=[Security(verify)])
def list_peers():
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
def add_peer(peer: PeerAdd):
    allowed = f"{peer.allowed_ip}/32"
    wg("set", WG_INTERFACE, "peer", peer.public_key, "allowed-ips", allowed)
    return {"public_key": peer.public_key, "allowed_ip": allowed}


@app.delete("/peers/{public_key}", status_code=204, dependencies=[Security(verify)])
def remove_peer(public_key: str):
    wg("set", WG_INTERFACE, "peer", public_key, "remove")