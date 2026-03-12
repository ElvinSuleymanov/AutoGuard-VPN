from flask import Flask, abort, request
from functools import wraps
import secrets
import os

app = Flask(__name__)

AUTH_KEY_SCRIPT = os.getenv("AUTH_KEY_SCRIPT")

def require_auth(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        user_provided_key = request.headers.get("X-Auth-Token")
        
        if not user_provided_key or not secrets.compare_digest(user_provided_key, AUTH_KEY_SCRIPT):
            abort(401)
            
        return f(*args, **kwargs)
    return decorated_function

@app.route("/", methods=["GET"])
@require_auth
def authenticate_client_script():
    #Below code is going to add public key of client to server and vice versa
    return {"public_key": os.getenv("SERVER_PUBLIC_KEY")}