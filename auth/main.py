import os
import requests;
from fastapi import FastAPI, Security
from helpers import verify
app = FastAPI()

@app.get("/", dependencies=[Security(verify)])
def authenticate_client_script():
    requests.post()
    return {"public_key": os.environ["SERVER_PUBLIC_KEY"]}