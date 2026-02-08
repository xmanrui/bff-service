from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.item import Item


class ItemRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_by_id(self, item_id: int) -> Item | None:
        return await self.db.get(Item, item_id)

    async def list(self, *, skip: int = 0, limit: int = 20) -> list[Item]:
        stmt = select(Item).offset(skip).limit(limit)
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def create(self, item: Item) -> Item:
        self.db.add(item)
        await self.db.commit()
        await self.db.refresh(item)
        return item
