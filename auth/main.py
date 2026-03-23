import os
import requests;
from fastapi import FastAPI, Security
from helpers import verify
app = FastAPI()

 
@app.get("/health")
def health_check():
    try:
        os.subprocess.run(["wg show wg0"], check=True, capture_output=True)
        return {"status":"ok"}
    except:
        return {"status":"wg0 is not ready"}

@app.get("/", dependencies=[Security(verify)])
def authenticate_client_script():
    requests.post()
    return {"public_key": os.environ["SERVER_PUBLIC_KEY"]}