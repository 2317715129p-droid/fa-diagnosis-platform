#!/usr/bin/env bash
# FA Diagnosis System — Server Cleanup Script
# ==============================================
# This script completely removes old FA deployment to free up disk space.
# Use when you need to do a fresh deployment.
#
# WARNING: This will DELETE all data!
#   - All running containers
#   - All Docker volumes (PostgreSQL data, Redis data, Weaviate data, Ollama models)
#   - All Docker images related to FA/Dify
#   - The /opt/fa installation directory
#
# Usage: sudo bash deploy/cleanup.sh [--force]

set -euo pipefail

INSTALL_DIR="/opt/fa"
PROJECT_NAME="fa"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
log_warn() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $*" >&2; }
log_error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; }

FORCE=0
if [[ "${1:-}" == "--force" ]]; then
  FORCE=1
fi

echo "=============================================="
echo "  FA Diagnosis System — Server Cleanup"
echo "=============================================="
echo
echo "This will REMOVE:"
echo "  1. All running FA/Dify containers"
echo "  2. All Docker volumes with data"
echo "  3. All FA/Dify Docker images"
echo "  4. The /opt/fa installation directory"
echo
echo "This CANNOT be undone!"
echo

if [[ $FORCE -eq 0 ]]; then
  read -r -p "Type YES to confirm cleanup: " confirm
  if [[ "$confirm" != "YES" ]]; then
    echo "Cleanup cancelled."
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Step 1: Stop and remove containers
# ---------------------------------------------------------------------------
log "Step 1: Stopping and removing containers..."

cd "$INSTALL_DIR" 2>/dev/null || cd /opt/fa 2>/dev/null || true

# Try docker compose down first
if command -v docker-compose >/dev/null 2>&1; then
  COMPOSE="docker-compose"
elif docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
else
  COMPOSE="docker-compose"
fi

if [[ -f "$INSTALL_DIR/docker-compose.yml" ]]; then
  cd "$INSTALL_DIR"
  $COMPOSE -p "$PROJECT_NAME" down --volumes --remove-orphans 2>/dev/null || true
  log "Docker Compose services stopped and removed"
else
  log_warn "docker-compose.yml not found in $INSTALL_DIR"
fi

# Force remove any remaining FA containers
REMAINING=$(docker ps -a --filter "name=fa-" --filter "name=dify-" -q 2>/dev/null || true)
if [[ -n "$REMAINING" ]]; then
  log "Force removing remaining containers..."
  docker rm -f $REMAINING 2>/dev/null || true
fi

# Remove any container with fa or dify in the name
docker ps -a | grep -E '(fa-|dify-)' | awk '{print $1}' | xargs -r docker rm -f 2>/dev/null || true

log "Containers cleaned"

# ---------------------------------------------------------------------------
# Step 2: Remove Docker volumes
# ---------------------------------------------------------------------------
log "Step 2: Removing Docker volumes..."

# Remove fa_ prefixed volumes
FA_VOLUMES=$(docker volume ls -q | grep "^fa_" || true)
if [[ -n "$FA_VOLUMES" ]]; then
  log "Removing fa_ volumes: $FA_VOLUMES"
  echo "$FA_VOLUMES" | xargs -r docker volume rm 2>/dev/null || true
fi

# Remove any remaining volumes that might be from our project
docker volume ls | grep -E '(fa_|dify)' | awk '{print $2}' | xargs -r docker volume rm -f 2>/dev/null || true

log "Volumes cleaned"

# ---------------------------------------------------------------------------
# Step 3: Remove Docker images
# ---------------------------------------------------------------------------
log "Step 3: Removing Docker images..."

# Remove FA and Dify related images
IMAGES_TO_REMOVE=(
  "fa-backend"
  "fa-frontend"
  "langgenius/dify-api"
  "langgenius/dify-web"
  "langgenius/dify-plugin-daemon"
  "langgenius/dify-sandbox"
  "ollama/ollama"
  "semitechnologies/weaviate"
  "postgres"
  "redis"
  "python"
  "nginx"
  "busybox"
  "ubuntu/squid"
)

for img in "${IMAGES_TO_REMOVE[@]}"; do
  # Get all tags for this image
  TAGS=$(docker images "$img" --format "{{.Repository}}:{{.Tag}}" 2>/dev/null || true)
  if [[ -n "$TAGS" ]]; then
    log "Removing image: $img"
    echo "$TAGS" | xargs -r docker rmi -f 2>/dev/null || true
  fi
done

log "Images cleaned"

# ---------------------------------------------------------------------------
# Step 4: Clean Docker build cache and dangling resources
# ---------------------------------------------------------------------------
log "Step 4: Cleaning Docker build cache..."

# Remove dangling images
docker image prune -f 2>/dev/null || true

# Remove all stopped containers
docker container prune -f 2>/dev/null || true

# Remove unused volumes (not used by any container)
docker volume prune -f 2>/dev/null || true

# Clean build cache
docker builder prune -f 2>/dev/null || true

log "Docker cache cleaned"

# ---------------------------------------------------------------------------
# Step 5: Remove installation directory
# ---------------------------------------------------------------------------
log "Step 5: Removing installation directory..."

if [[ -d "$INSTALL_DIR" ]]; then
  rm -rf "$INSTALL_DIR"
  log "Removed $INSTALL_DIR"
else
  log "$INSTALL_DIR does not exist"
fi

# ---------------------------------------------------------------------------
# Step 6: Report disk space freed
# ---------------------------------------------------------------------------
log "Step 6: Checking disk space..."

echo
echo "=============================================="
echo "  Cleanup Complete!"
echo "=============================================="
echo
echo "  Docker disk usage:"
docker system df 2>/dev/null || echo "  (Docker not running)"
echo
echo "  Root filesystem:"
df -h / 2>/dev/null || true
echo
echo "  To deploy the new version:"
echo "    1. Copy fa-diagnosis-offline.tar.gz to server"
echo "    2. tar -xzf fa-diagnosis-offline.tar.gz -C /opt/fa"
echo "    3. cd /opt/fa && sudo bash deploy/install.sh --skip-confirm"
echo
echo "=============================================="
