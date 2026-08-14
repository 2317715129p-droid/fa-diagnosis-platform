# Fix note: config already used python-dotenv; keep defaults aligned with Nginx
# on port 80 (http://localhost) and ensure .env overrides defaults.

import os
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

DIFY_API_URL = os.getenv("DIFY_API_URL", "http://localhost")
DIFY_API_KEY = os.getenv("DIFY_API_KEY", "")
DIFY_TRANSLATE_API_KEY = os.getenv("DIFY_TRANSLATE_API_KEY", "")

_db_url = os.getenv("DATABASE_URL", "sqlite:///fa_data.db")
if _db_url.startswith("sqlite:///"):
    _raw = _db_url.replace("sqlite:///", "", 1)
    if _raw and not _raw.startswith(":memory:"):
        Path(_raw).parent.mkdir(parents=True, exist_ok=True)

DATABASE_URL = _db_url
