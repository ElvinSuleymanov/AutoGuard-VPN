
from pydantic import BaseModel


class PeerAdd(BaseModel):
    public_key: str
    