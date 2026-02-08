from httpx import AsyncClient


async def test_list_users(client: AsyncClient):
    response = await client.get("/api/v1/users/")
    assert response.status_code == 200
