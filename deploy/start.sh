#!/usr/bin/env bash
# FA Diagnosis System — one-shot Docker deploy
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "=============================================="
echo "  FA Diagnosis System — Docker deploy"
echo "=============================================="
echo

# --- Docker ---
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: Docker is not installed."
  echo "  Install: https://docs.docker.com/engine/install/"
  exit 1
fi

if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  echo "ERROR: Docker Compose is not installed."
  echo "  Install: https://docs.docker.com/compose/install/"
  exit 1
fi

echo "[ok] Docker: $(docker --version)"
echo "[ok] Compose: $(${COMPOSE[@]} version 2>/dev/null | head -1)"
echo

# Offline: load pre-saved images if present
if [[ -f deploy-images.tar ]]; then
  echo "[..] Found deploy-images.tar — loading into Docker (offline)..."
  docker load -i deploy-images.tar
  echo "[ok] Images loaded"
  echo
fi

if [[ ! -d offline-packages ]] || [[ -z "$(ls -A offline-packages 2>/dev/null | grep -v gitkeep || true)" ]]; then
  echo "WARN: offline-packages/ is empty. Backend build needs wheels for offline hosts."
  echo "      Run deploy/offline-prep.sh on a machine with internet first."
  echo
fi

if [[ ! -d dist ]]; then
  echo "WARN: dist/ missing. Frontend Dockerfile expects a pre-built dist/ for offline."
  echo "      Run: npm ci && npm run build   (or deploy/offline-prep.sh)"
  echo
fi

# --- .env ---
if [[ ! -f .env ]]; then
  if [[ -f .env.example ]]; then
    cp .env.example .env
    echo "[ok] Created .env from .env.example"
  else
    echo "ERROR: .env.example not found"
    exit 1
  fi
else
  echo "[ok] .env already exists"
fi

echo
echo "IMPORTANT: Edit .env and set at least:"
echo "  - DIFY_API_KEY           (diagnosis workflow API key from Dify)"
echo "  - DIFY_TRANSLATE_API_KEY (translate workflow API key, optional)"
echo "  - DIFY_SECRET_KEY / passwords for production"
echo
echo "  For INTRANET deployment (no internet):"
echo "    1. Login to Dify at http://<host>:80 (admin/admin123456)"
echo "    2. Configure Ollama at Settings → Model Providers → Ollama"
echo "       Set API Base URL: http://ollama:11434"
echo "    3. Pull model: docker exec -it fa-ollama ollama pull qwen2:7b"
echo "    4. Create workflow and get API key"
echo "    5. Paste API key into .env and restart backend"
echo

if [[ -t 0 ]]; then
  read -r -p "Press Enter after you have reviewed/edited .env (or Ctrl+C to abort)..."
fi

echo
echo "[..] Starting stack (offline hosts: images must already be loaded)..."
"${COMPOSE[@]}" up -d --build

echo
echo "=============================================="
echo "  Services"
echo "=============================================="
echo "  FA UI (diagnose):     http://localhost:3000"
echo "  FA API / health:      http://localhost:8000/health"
echo "  FA API docs:          http://localhost:8000/docs"
echo "  Dify console:         http://localhost:80"
echo "  Ollama local LLM:     http://localhost:11434"
echo
echo "  Agent install (from monitored Linux host):"
echo "    curl -fsSL \"http://<THIS_HOST_IP>:8000/api/agent/install.sh?server_id=Node-01\" | sudo bash"
echo
echo "  Useful commands:"
echo "    ${COMPOSE[*]} ps"
echo "    ${COMPOSE[*]} logs -f backend"
echo "    ${COMPOSE[*]} down"
echo "=============================================="
