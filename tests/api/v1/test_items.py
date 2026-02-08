from httpx import AsyncClient


async def test_list_items(client: AsyncClient):
    response = await client.get("/api/v1/items/")
    assert response.status_code == 200
