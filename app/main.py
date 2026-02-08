from fastapi import FastAPI

from app.api.v1.router import router as v1_router
from app.config import settings
from app.core.exceptions import register_exception_handlers
from app.core.middleware import register_middleware


def create_app() -> FastAPI:
    app = FastAPI(
        title=settings.app_name,
        debug=settings.debug,
    )
    register_middleware(app)
    register_exception_handlers(app)
    app.include_router(v1_router, prefix="/api/v1")
    return app


app = create_app()
