# FA Diagnosis System — Backend (FastAPI)
# Offline-friendly: install from pre-downloaded wheels in offline-packages/
FROM python:3.11-slim

WORKDIR /app

# No apt-get (intranet hosts often have no package mirrors).
# Healthcheck uses Python stdlib instead of curl.

COPY requirements.txt .
COPY offline-packages /offline-packages
RUN pip install --no-cache-dir --no-index --find-links=/offline-packages -r requirements.txt

COPY . .

# Persist SQLite (DATABASE_URL=sqlite:///data/fa_data.db)
RUN mkdir -p /app/data /app/static/reports

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
