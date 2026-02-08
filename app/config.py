from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_name: str = "bff-service"
    debug: bool = False
    database_url: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/bff_service"
    secret_key: str = "change-me-in-production"
    access_token_expire_minutes: int = 30

    model_config = {"env_file": ".env"}


settings = Settings()
