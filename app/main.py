from fastapi import FastAPI
from fastapi.responses import PlainTextResponse

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

    @app.get("/health", response_class=PlainTextResponse)
    async def health_check():
        return "ok"

    return app


app = create_app()

if __name__ == "__main__":
    import uvicorn

    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True)
