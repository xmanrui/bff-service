from pydantic import BaseModel


class ItemCreate(BaseModel):
    title: str
    description: str | None = None
    owner_id: int


class ItemResponse(BaseModel):
    id: int
    title: str
    description: str | None
    owner_id: int

    model_config = {"from_attributes": True}
