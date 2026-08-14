#!/usr/bin/env bash
# Prepare an offline bundle for intranet servers with NO internet access.
# Run this on a machine that HAS internet + Docker + Node.js + Python/pip.
#
# Dify 1.15.0 images:
#   - If dify-full-1.15.0.tar exists in the project root, it will be loaded
#     first (contains dify-api:1.15.0, dify-web:1.15.0, plugin-daemon:0.6.3-local).
#   - Remaining images (sandbox, ssrf-proxy, weaviate, postgres, redis, busybox)
#     are pulled from the internet.
#
# Output: fa-diagnosis-offline.tar.gz  (copy to the target server)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "=============================================="
echo "  FA Diagnosis — offline prep (Dify 1.15.0)"
echo "=============================================="
echo "  Working dir: $ROOT_DIR"
echo

# Base images required by FA + Dify 1.15.0 (pinned tags only)
IMAGES=(
  "python:3.11-slim"
  "nginx:1.27-alpine"
  "busybox:1.36.1"
  "langgenius/dify-sandbox:0.2.15"
  "ubuntu/squid:latest"
  "postgres:15-alpine"
  "redis:6-alpine"
  "semitechnologies/weaviate:1.27.0"
  "ollama/ollama:0.5.7"
)

# Dify 1.15.0 core images that may come from a pre-built tar
DIFY_TAR="$ROOT_DIR/dify-full-1.15.0.tar"
DIFY_IMAGES=(
  "langgenius/dify-api:1.15.0"
  "langgenius/dify-web:1.15.0"
  "langgenius/dify-plugin-daemon:0.6.3-local"
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
# a) Load pre-built Dify 1.15.0 images if available
# ---------------------------------------------------------------------------
if [[ -f "$DIFY_TAR" ]]; then
  echo "[0/4] Found $DIFY_TAR — loading Dify 1.15.0 images..."
  docker load -i "$DIFY_TAR"
  for img in "${DIFY_IMAGES[@]}"; do
    if ! docker images -q "$img" >/dev/null 2>&1; then
      echo "ERROR: $DIFY_TAR did not contain expected image: $img"
      exit 1
    fi
    echo "  -> loaded $img"
  done
else
  echo "[0/4] $DIFY_TAR not found — will pull Dify 1.15.0 images from Docker Hub."
  IMAGES+=("${DIFY_IMAGES[@]}")
fi
echo

# ---------------------------------------------------------------------------
# b) docker pull all required images
# ---------------------------------------------------------------------------
echo "[1/4] Pulling Docker images..."
for img in "${IMAGES[@]}"; do
  echo "  -> docker pull $img"
  docker pull "$img"
done
echo

# ---------------------------------------------------------------------------
# c) docker save (include Dify images whether loaded or pulled)
# ---------------------------------------------------------------------------
ALL_IMAGES=("${IMAGES[@]}" "${DIFY_IMAGES[@]}")

echo "[2/4] Saving images to deploy-images.tar ..."
docker save -o deploy-images.tar "${ALL_IMAGES[@]}"
ls -lh deploy-images.tar
echo

# ---------------------------------------------------------------------------
# d) build & save fa-backend (offline Dockerfile, wheels from offline-packages)
# ---------------------------------------------------------------------------
echo "[2b] Building & saving fa-backend:1.0.0 ..."
# Use a clean temp build context to avoid shipping node_modules / large dirs
TMP_BUILD="$(mktemp -d)"
cp backend/Dockerfile "$TMP_BUILD/Dockerfile"
cp backend/requirements.txt "$TMP_BUILD/requirements.txt"
cp -r offline-packages "$TMP_BUILD/offline-packages"
cp main.py config.py "$TMP_BUILD/"
cp -r api models services src "$TMP_BUILD/"
docker build -t fa-backend:1.0.0 -f "$TMP_BUILD/Dockerfile" "$TMP_BUILD"
rm -rf "$TMP_BUILD"
docker save -o fa-backend.tar fa-backend:1.0.0
ls -lh fa-backend.tar
echo

# ---------------------------------------------------------------------------
# e) pip download wheels (linux/amd64 + py3.11 — matches python:3.11-slim)
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
# f) Frontend pre-build (dist/) — target host skips npm build
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
# g) pack offline tarball
# ---------------------------------------------------------------------------
echo "[4/4] Creating fa-diagnosis-offline.tar.gz ..."
OUT=fa-diagnosis-offline.tar.gz

rm -f "$OUT"

tar -czf "$OUT" \
  deploy-images.tar \
  fa-backend.tar \
  offline-packages \
  dist \
  backend \
  frontend \
  dify \
  ssrf_proxy \
  volumes/sandbox/conf \
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
