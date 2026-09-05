"""Entrypoint: `python run.py` (from anywhere) starts the API server."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import uvicorn  # noqa: E402

from config import settings  # noqa: E402

if __name__ == "__main__":
    uvicorn.run("server:app", host=settings.host, port=settings.port, reload=True, app_dir=str(Path(__file__).resolve().parent))
