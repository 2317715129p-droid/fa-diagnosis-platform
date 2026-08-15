#!/usr/bin/env bash
# Prepare an offline bundle for intranet servers with NO internet access.
# Run this on a machine that HAS internet + Docker + Node.js + Python/pip.
#
# Output: fa-diagnosis-offline.tar.gz  (copy to the target server)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "=============================================="
echo "  FA Diagnosis — offline prep"
echo "=============================================="
echo "  Working dir: $ROOT_DIR"
echo

# Keep in sync with docker-compose.yml / Dockerfiles (pinned tags only)
IMAGES=(
  "python:3.11-slim"
  "nginx:1.27-alpine"
  "langgenius/dify-api:1.1.3"
  "langgenius/dify-web:1.1.3"
  "postgres:15.8-alpine"
  "redis:6.2.14-alpine"
  "semitechnologies/weaviate:1.19.0"
  "ollama/ollama:0.5.7"
)

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1"
    exit 1
  }
}

need docker
need pip
need npm
need tar

# ---------------------------------------------------------------------------
# a) docker pull all required images
# ---------------------------------------------------------------------------
echo "[1/4] Pulling Docker images..."
for img in "${IMAGES[@]}"; do
  echo "  -> docker pull $img"
  docker pull "$img"
done
echo

# ---------------------------------------------------------------------------
# b) docker save
# ---------------------------------------------------------------------------
echo "[2/4] Saving images to deploy-images.tar ..."
docker save -o deploy-images.tar "${IMAGES[@]}"
ls -lh deploy-images.tar
echo

# ---------------------------------------------------------------------------
# c) pip download wheels (linux/amd64 + py3.11 — matches python:3.11-slim)
# ---------------------------------------------------------------------------
echo "[3/4] Downloading Python wheels into offline-packages/ ..."
rm -rf offline-packages
mkdir -p offline-packages

REQ_FILE="backend/requirements.txt"
if [[ ! -f "$REQ_FILE" ]]; then
  REQ_FILE="requirements.txt"
fi

# Prefer manylinux wheels so the bundle works inside python:3.11-slim on Linux
if ! pip download \
  -r "$REQ_FILE" \
  -d offline-packages \
  --python-version 311 \
  --platform manylinux2014_x86_64 \
  --implementation cp \
  --abi cp311 \
  --only-binary=:all:; then
  echo "WARN: binary-only download failed; falling back to host platform wheels"
  pip download -r "$REQ_FILE" -d offline-packages
fi

cp -f "$REQ_FILE" backend/requirements.txt
cp -f "$REQ_FILE" requirements.txt

echo "  packages: $(find offline-packages -type f | wc -l)"
echo

# ---------------------------------------------------------------------------
# Frontend pre-build (dist/) — target host skips npm build
# ---------------------------------------------------------------------------
echo "[3b] Building frontend dist/ ..."
if [[ ! -d node_modules ]]; then
  npm ci
fi
npm run build
test -d dist || {
  echo "ERROR: dist/ missing after npm run build"
  exit 1
}
echo

# ---------------------------------------------------------------------------
# d) pack offline tarball
# ---------------------------------------------------------------------------
echo "[4/4] Creating fa-diagnosis-offline.tar.gz ..."
OUT=fa-diagnosis-offline.tar.gz

tar -czf "$OUT" \
  deploy-images.tar \
  offline-packages \
  dist \
  backend \
  frontend \
  dify \
  deploy \
  docker-compose.yml \
  .env.example \
  .env.offline.example \
  .dockerignore \
  requirements.txt \
  main.py \
  config.py \
  api \
  models \
  services \
  src \
  static \
  package.json \
  package-lock.json \
  index.html \
  vite.config.js \
  docker-26.1.4.tgz \
  docker-compose-bin

ls -lh "$OUT"
echo
echo "=============================================="
echo "  Done"
echo "=============================================="
echo "  Bundle: $ROOT_DIR/$OUT"
echo
echo "  On the intranet server:"
echo "    # One-click install (recommended):"
echo "    mkdir -p /opt/fa && tar -xzf fa-diagnosis-offline.tar.gz -C /opt/fa"
echo "    cd /opt/fa && sudo bash deploy/install.sh --skip-confirm"
echo "=============================================="
