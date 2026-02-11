from fastapi import FastAPI
from fastapi.responses import HTMLResponse, PlainTextResponse

from app.api.v1.router import router as v1_router
from app.config import settings
from app.core.exceptions import register_exception_handlers
from app.core.middleware import register_middleware

WELCOME_HTML = """<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>BFF Service</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    min-height: 100vh;
    display: flex; align-items: center; justify-content: center;
    background: linear-gradient(135deg, #e65100, #ff9800, #ffb74d);
    color: #fff;
  }
  .container { text-align: center; padding: 2rem; }
  .logo { font-size: 4rem; margin-bottom: 1rem; }
  h1 { font-size: 2.5rem; margin-bottom: 0.5rem; }
  .subtitle { font-size: 1.1rem; color: #a0a0c0; margin-bottom: 2rem; }
  .links { display: flex; gap: 1rem; justify-content: center; flex-wrap: wrap; }
  .links a {
    padding: 0.6rem 1.5rem; border-radius: 8px;
    text-decoration: none; color: #fff; font-size: 0.95rem;
    background: rgba(255,255,255,0.1); border: 1px solid rgba(255,255,255,0.2);
    transition: background 0.2s;
  }
  .links a:hover { background: rgba(255,255,255,0.2); }
  .status { margin-top: 2rem; font-size: 0.85rem; color: #6a6a8a; }
</style>
</head>
<body>
<div class="container">
  <div class="logo">🚀</div>
  <h1>BFF Service</h1>
  <p class="subtitle">Built with FastAPI · Ready to serve</p>
  <div class="links">
    <a href="/docs">📖 API Docs</a>
    <a href="/redoc">📚 ReDoc</a>
    <a href="/health">💚 Health</a>
    <a href="/api/v1/users">👥 Users</a>
    <a href="/api/v1/items">📦 Items</a>
  </div>
  <p class="status">✅ Service is running</p>
</div>
</body>
</html>"""


def create_app() -> FastAPI:
    app = FastAPI(
        title=settings.app_name,
        debug=settings.debug,
    )
    register_middleware(app)
    register_exception_handlers(app)
    app.include_router(v1_router, prefix="/api/v1")

    @app.get("/", response_class=HTMLResponse)
    async def welcome():
        return WELCOME_HTML

    @app.get("/health", response_class=PlainTextResponse)
    async def health_check():
        return "ok"

    return app


app = create_app()

if __name__ == "__main__":
    import uvicorn

    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True)
