from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.dependencies import get_db
from app.schemas.item import ItemCreate, ItemResponse
from app.services.item_service import ItemService

router = APIRouter()


@router.get("/", response_model=list[ItemResponse])
async def list_items(
    skip: int = 0,
    limit: int = 20,
    db: AsyncSession = Depends(get_db),
):
    service = ItemService(db)
    return await service.list_items(skip=skip, limit=limit)


@router.get("/{item_id}", response_model=ItemResponse)
async def get_item(
    item_id: int,
    db: AsyncSession = Depends(get_db),
):
    service = ItemService(db)
    return await service.get_item(item_id)


@router.post("/", response_model=ItemResponse, status_code=201)
async def create_item(
    body: ItemCreate,
    db: AsyncSession = Depends(get_db),
):
    service = ItemService(db)
    return await service.create_item(body)
