from fastapi import HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.item import Item
from app.repositories.item_repo import ItemRepository
from app.schemas.item import ItemCreate


class ItemService:
    def __init__(self, db: AsyncSession):
        self.repo = ItemRepository(db)

    async def get_item(self, item_id: int) -> Item:
        item = await self.repo.get_by_id(item_id)
        if not item:
            raise HTTPException(status_code=404, detail="Item not found")
        return item

    async def list_items(self, *, skip: int = 0, limit: int = 20) -> list[Item]:
        return await self.repo.list(skip=skip, limit=limit)

    async def create_item(self, data: ItemCreate) -> Item:
        item = Item(
            title=data.title,
            description=data.description,
            owner_id=data.owner_id,
        )
        return await self.repo.create(item)
