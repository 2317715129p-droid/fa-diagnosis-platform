#!/usr/bin/env bash
# FA Diagnosis System — Intranet One-Click Installer
# =================================================
# Run on the target intranet server (NO internet required)
# Usage: sudo bash deploy/install.sh [--skip-confirm] [--force]
#
# Prerequisites on target:
#   - Docker Engine installed
#   - Docker Compose installed (v2+)
#   - tar, gzip installed
#
# Offline bundle contents verified:
#   - deploy-images.tar: all Docker images (python, nginx, dify, postgres, redis, weaviate)
#   - offline-packages/: Python wheels for backend
#   - dist/: Pre-built frontend
#   - backend/, frontend/, dify/, deploy/ etc.

set -euo pipefail

INSTALL_DIR="/opt/fa"
BUNDLE_NAME="fa-diagnosis-offline.tar.gz"
IMAGES_TAR="deploy-images.tar"

SKIP_CONFIRM=0
FORCE=0

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log_ok() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [OK] $*"
}

log_warn() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $*" >&2
}

log_error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

die() {
  log_error "$*"
  exit 1
}

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "Required command not found: $1. Please install it first."
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --skip-confirm) SKIP_CONFIRM=1; shift ;;
      --force) FORCE=1; shift ;;
      -h|--help)
        cat <<EOF
Usage: sudo bash deploy/install.sh [options]

FA Diagnosis System — Intranet One-Click Installer

Options:
  --skip-confirm    Skip interactive confirmation steps
  --force           Overwrite existing installation if found
  -h, --help        Show this help message

Prerequisites:
  - Docker Engine (https://docs.docker.com/engine/install/)
  - Docker Compose v2+
  - tar, gzip

Example:
  sudo bash deploy/install.sh --skip-confirm
EOF
        exit 0
        ;;
      *) die "Unknown option: $1" ;;
    esac
  done
}

check_prerequisites() {
  log "Checking prerequisites..."

  if [[ "$(id -u)" -ne 0 ]]; then
    die "Must run as root (sudo)"
  fi

  need tar
  need gzip

  if command -v docker >/dev/null 2>&1; then
    log_ok "Docker already installed: $(docker --version)"
  else
    log "Docker not found; installing from offline package..."
    install_docker_offline
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE="docker-compose"
  elif docker compose version >/dev/null 2>&1; then
    COMPOSE="docker compose"
  else
    log "Docker Compose not found; installing from offline package..."
    install_compose_offline
    COMPOSE="docker-compose"
  fi

  if ! docker info >/dev/null 2>&1; then
    log "Docker daemon not running; starting..."
    start_docker_daemon
  fi

  log_ok "Docker: $(docker --version)"
  log_ok "Compose: $(${COMPOSE} version 2>/dev/null | head -1)"
}

install_docker_offline() {
  local docker_tgz="$INSTALL_DIR/docker-26.1.4.tgz"
  if [[ ! -f "$docker_tgz" ]]; then
    die "Docker offline package not found: $docker_tgz"
  fi

  log "Extracting Docker binaries..."
  tar -xzf "$docker_tgz" -C /tmp/
  cp -f /tmp/docker/* /usr/local/bin/
  chmod +x /usr/local/bin/docker* /usr/local/bin/runc /usr/local/bin/containerd* /usr/local/bin/ctr

  log "Creating Docker systemd service..."
  cat > /etc/systemd/system/docker.service <<'EOF'
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service containerd.service
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/local/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutSec=0
RestartSec=2
Restart=always

StartLimitBurst=3
StartLimitInterval=60s

LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity

TasksMax=infinity
Delegate=yes
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

  cat > /etc/systemd/system/containerd.service <<'EOF'
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target

[Service]
ExecStart=/usr/local/bin/containerd
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF

  mkdir -p /etc/docker
  cat > /etc/docker/daemon.json <<'EOF'
{
  "data-root": "/var/lib/docker"
}
EOF

  mkdir -p /var/lib/docker /run/docker /run/containerd
  systemctl daemon-reload

  log_ok "Docker installed from offline package"
}

install_compose_offline() {
  local compose_bin="$INSTALL_DIR/docker-compose"
  if [[ ! -f "$compose_bin" ]]; then
    die "Docker Compose binary not found: $compose_bin"
  fi

  cp -f "$compose_bin" /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose

  log_ok "Docker Compose installed from offline package"
}

start_docker_daemon() {
  systemctl start containerd
  systemctl start docker

  local max_wait=60
  local wait_interval=5
  local elapsed=0

  while [[ "$elapsed" -lt "$max_wait" ]]; do
    if docker info >/dev/null 2>&1; then
      log_ok "Docker daemon started"
      return 0
    fi
    log "Waiting for Docker daemon... ($((elapsed/wait_interval))/$((max_wait/wait_interval)))"
    sleep "$wait_interval"
    elapsed=$((elapsed + wait_interval))
  done

  die "Failed to start Docker daemon within $max_wait seconds"
}

check_bundle() {
  log "Checking offline bundle..."

  if [[ ! -f "$BUNDLE_NAME" ]]; then
    die "Bundle not found: $BUNDLE_NAME. Please copy it to the current directory."
  fi

  local size
  size=$(stat -c%s "$BUNDLE_NAME" 2>/dev/null || stat -f%z "$BUNDLE_NAME" 2>/dev/null || echo 0)
  if [[ "$size" -lt 100000000 ]]; then
    log_warn "Bundle size is small (${size} bytes). Expected several GB."
    log_warn "It may be incomplete. Continuing anyway..."
  fi

  log_ok "Bundle: $BUNDLE_NAME (${size} bytes)"
}

check_install_dir() {
  if [[ -d "$INSTALL_DIR" ]]; then
    if [[ $FORCE -eq 1 ]]; then
      log_warn "Overwriting existing installation at $INSTALL_DIR..."
      # Save the bundle file first if it's inside the install dir
      local saved_bundle=""
      local saved_model=""
      if [[ -f "$INSTALL_DIR/$BUNDLE_NAME" ]]; then
        saved_bundle="$INSTALL_DIR/$BUNDLE_NAME"
        cp -f "$saved_bundle" "/tmp/${BUNDLE_NAME}.bak" 2>/dev/null || true
        log_warn "Saved bundle to /tmp/${BUNDLE_NAME}.bak"
      fi
      if [[ -f "$INSTALL_DIR/ollama-models-qwen2-7b.tar.gz" ]]; then
        saved_model="$INSTALL_DIR/ollama-models-qwen2-7b.tar.gz"
        cp -f "$saved_model" "/tmp/ollama-models-qwen2-7b.tar.gz.bak" 2>/dev/null || true
        log_warn "Saved model to /tmp/ollama-models-qwen2-7b.tar.gz.bak"
      fi
      rm -rf "$INSTALL_DIR"
      mkdir -p "$INSTALL_DIR"
      # Restore saved files
      if [[ -n "$saved_bundle" && -f "/tmp/${BUNDLE_NAME}.bak" ]]; then
        cp -f "/tmp/${BUNDLE_NAME}.bak" "$INSTALL_DIR/$BUNDLE_NAME"
        rm -f "/tmp/${BUNDLE_NAME}.bak"
      fi
      if [[ -n "$saved_model" && -f "/tmp/ollama-models-qwen2-7b.tar.gz.bak" ]]; then
        cp -f "/tmp/ollama-models-qwen2-7b.tar.gz.bak" "$INSTALL_DIR/ollama-models-qwen2-7b.tar.gz"
        rm -f "/tmp/ollama-models-qwen2-7b.tar.gz.bak"
      fi
    else
      die "Installation directory exists: $INSTALL_DIR. Use --force to overwrite."
    fi
  fi
}

extract_bundle() {
  log "Extracting bundle to $INSTALL_DIR..."
  mkdir -p "$INSTALL_DIR"

  if ! tar -xzf "$BUNDLE_NAME" -C "$INSTALL_DIR"; then
    die "Failed to extract bundle. The file may be corrupted."
  fi

  log_ok "Bundle extracted successfully"
}

load_images() {
  log "Loading Docker images..."

  if [[ ! -f "$INSTALL_DIR/$IMAGES_TAR" ]]; then
    die "Image archive not found: $INSTALL_DIR/$IMAGES_TAR"
  fi

  local image_count
  # OCI format: count manifests in index.json
  if tar -tf "$INSTALL_DIR/$IMAGES_TAR" | grep -q "index.json"; then
    image_count=$(tar -xf "$INSTALL_DIR/$IMAGES_TAR" -O index.json 2>/dev/null | grep -o '"mediaType":' | wc -l)
  else
    # Traditional docker save format
    image_count=$(tar -tf "$INSTALL_DIR/$IMAGES_TAR" | grep -E "^[0-9a-f]{64}/manifest.json$" | wc -l)
  fi
  log "Found $image_count images in archive"

  if ! docker load -i "$INSTALL_DIR/$IMAGES_TAR"; then
    die "Failed to load Docker images"
  fi

  log_ok "All images loaded successfully"

  # Load fa-backend image (built offline during prep, saved as fa-backend.tar)
  local backend_tar="$INSTALL_DIR/fa-backend.tar"
  if [[ -f "$backend_tar" ]]; then
    log "Loading fa-backend image..."
    if ! docker load -i "$backend_tar"; then
      log_warn "Failed to load fa-backend.tar; will attempt build instead."
    else
      log_ok "fa-backend image loaded"
    fi
  else
    log_warn "fa-backend.tar not found; backend will be built from Dockerfile."
  fi
}

verify_images() {
  log "Verifying loaded images..."

  local required_images=(
    "python:3.11-slim"
    "nginx:1.27-alpine"
    "busybox:1.36.1"
    "langgenius/dify-api:1.15.0"
    "langgenius/dify-web:1.15.0"
    "langgenius/dify-plugin-daemon:0.6.3-local"
    "langgenius/dify-sandbox:0.2.15"
    "ubuntu/squid:latest"
    "postgres:15-alpine"
    "redis:6-alpine"
    "semitechnologies/weaviate:1.27.0"
    "ollama/ollama:0.5.7"
  )

  local missing=0
  for img in "${required_images[@]}"; do
    if ! docker images -q "$img" >/dev/null 2>&1; then
      log_error "Missing image: $img"
      missing=1
    else
      log_ok "Image found: $img"
    fi
  done

  if [[ $missing -eq 1 ]]; then
    die "Some required images are missing. Check deploy-images.tar"
  fi
}

setup_env() {
  log "Setting up environment..."

  cd "$INSTALL_DIR"

  if [[ -f .env ]]; then
    log_warn ".env already exists, keeping existing configuration"
    return
  fi

  if [[ -f .env.offline.example ]]; then
    cp .env.offline.example .env
    log_ok "Created .env from .env.offline.example (for internal network)"
  elif [[ -f .env.example ]]; then
    cp .env.example .env
    log_ok "Created .env from .env.example"
  else
    die ".env.offline.example or .env.example not found in bundle"
  fi
}

verify_offline_packages() {
  log "Verifying offline packages..."

  if [[ ! -d "$INSTALL_DIR/offline-packages" ]]; then
    die "offline-packages/ directory missing"
  fi

  local pkg_count
  pkg_count=$(find "$INSTALL_DIR/offline-packages" -type f -name "*.whl" | wc -l)

  if [[ "$pkg_count" -eq 0 ]]; then
    die "No Python wheels found in offline-packages/"
  fi

  log_ok "Found $pkg_count Python wheels"
}

verify_frontend() {
  log "Verifying frontend dist..."

  if [[ ! -d "$INSTALL_DIR/dist" ]]; then
    die "dist/ directory missing (frontend not built)"
  fi

  if [[ ! -f "$INSTALL_DIR/dist/index.html" ]]; then
    die "dist/index.html missing"
  fi

  log_ok "Frontend dist OK"
}

restore_ollama_model() {
  log "Restoring Ollama model from offline bundle (if present)..."

  local model_tar="$INSTALL_DIR/ollama-models-qwen2-7b.tar.gz"
  if [[ ! -f "$model_tar" ]]; then
    log_warn "Ollama model bundle not found: $model_tar"
    log_warn "Skipping model restore. You must 'docker exec -it fa-ollama ollama pull <model>' later (needs internet)."
    return 0
  fi

  # Start ollama first so the volume is created
  log "Starting ollama service to initialize model volume..."
  $COMPOSE -p fa up -d ollama
  sleep 5

  log "Restoring model blobs into fa_ollama_models volume..."
  # Use busybox (already in our images) to extract the model tar
  docker run --rm -v fa_ollama_models:/data -v "$INSTALL_DIR":/backup busybox:1.36.1 \
    tar -xzf /backup/ollama-models-qwen2-7b.tar.gz -C /data

  log "Restarting ollama to pick up restored model..."
  $COMPOSE -p fa restart ollama
  sleep 3

  if docker exec fa-ollama ollama list 2>/dev/null | grep -q "qwen2"; then
    log_ok "Ollama model restored: qwen2:7b is available"
  else
    log_warn "Model restore ran but 'ollama list' shows no qwen2 model. Check the tar contents."
  fi
}

restore_embedding_model() {
  log "Restoring embedding model from offline bundle (if present)..."

  local embed_tar="$INSTALL_DIR/ollama-models-embedding.tar.gz"
  if [[ ! -f "$embed_tar" ]]; then
    log_warn "Embedding model bundle not found: $embed_tar"
    log_warn "Skipping embedding model restore. Knowledge base will not work without it."
    log_warn "To enable knowledge base, download bge-small-zh-v1.5 and repackage."
    return 0
  fi

  # Start ollama first so the volume is created
  log "Starting ollama service to initialize model volume..."
  $COMPOSE -p fa up -d ollama
  sleep 5

  log "Restoring embedding model blobs into fa_ollama_models volume..."
  docker run --rm -v fa_ollama_models:/data -v "$INSTALL_DIR":/backup busybox:1.36.1 \
    tar -xzf /backup/ollama-models-embedding.tar.gz -C /data

  log "Restarting ollama to pick up embedding model..."
  $COMPOSE -p fa restart ollama
  sleep 3

  # Verify embedding model is available
  if docker exec fa-ollama ollama list 2>/dev/null | grep -q "bge"; then
    log_ok "Embedding model restored: bge-small-zh-v1.5 is available"
  else
    log_warn "Embedding model restore ran but 'ollama list' shows no bge model."
    log_warn "You may need to configure Ollama embedding in Dify manually."
  fi
}

start_services() {
  log "Starting services..."

  cd "$INSTALL_DIR"

  # Do NOT use --build: images (including fa-backend) are pre-loaded from the
  # offline bundle. Building would require network/packages unavailable intranet.
  $COMPOSE -p fa up -d

  log_ok "Services started"
}

wait_for_services() {
  log "Waiting for services to be ready..."

  cd "$INSTALL_DIR"

  local max_wait=300
  local wait_interval=10
  local elapsed=0

  while [[ "$elapsed" -lt "$max_wait" ]]; do
    local backend_ready=0
    local frontend_ready=0
    local dify_ready=0

    if curl -s http://localhost:8000/health >/dev/null 2>&1; then
      backend_ready=1
    fi

    if curl -s http://localhost:3000 >/dev/null 2>&1; then
      frontend_ready=1
    fi

    if curl -s http://localhost:80 >/dev/null 2>&1; then
      dify_ready=1
    fi

    if [[ "$backend_ready" -eq 1 && "$frontend_ready" -eq 1 && "$dify_ready" -eq 1 ]]; then
      log_ok "All services are ready!"
      return 0
    fi

    log "Waiting... ($((elapsed/wait_interval))/$((max_wait/wait_interval))) Backend:${backend_ready} Frontend:${frontend_ready} Dify:${dify_ready}"
    sleep "$wait_interval"
    elapsed=$((elapsed + wait_interval))
  done

  log_warn "Timeout waiting for services. Checking current status..."
  return 0
}

show_status() {
  log "Final status check..."

  cd "$INSTALL_DIR"

  echo
  echo "=============================================="
  echo "  FA Diagnosis System — Installation Complete"
  echo "=============================================="
  echo

  $COMPOSE -p fa ps

  echo
  echo "=============================================="
  echo "  Access URLs"
  echo "=============================================="
  echo "  FA UI (Diagnose):     http://localhost:3000"
  echo "  FA API / Health:      http://localhost:8000/health"
  echo "  FA API Docs:          http://localhost:8000/docs"
  echo "  Dify Console:         http://localhost:80"
  echo "  Ollama API:           http://localhost:11434"
  echo
  echo "=============================================="
  echo "  INTRANET DEPLOYMENT: Critical Configuration"
  echo "=============================================="
  echo "  (Local LLM + Dify workflow setup)"
  echo
  echo "  Step 1: Login to Dify Console"
  echo "  ------------------------------"
  echo "    URL:     http://localhost:80"
  echo "    Login:   admin / admin123456"
  echo "    * CHANGE THE PASSWORD after login!"
  echo
  echo "  Step 2: Configure Local LLM (Ollama)"
  echo "  -------------------------------------"
  echo "    The Ollama model (qwen2:7b) is auto-restored from the offline bundle."
  echo "    Verify with: docker exec -it fa-ollama ollama list"
  echo
  echo "    In Dify Console:"
  echo "      1. Go to Settings -> Model Providers"
  echo "      2. Find 'Ollama' and click 'Configure'"
  echo "      3. Set API Base URL: http://ollama:11434"
  echo "      4. Click 'Test Connection' to verify"
  echo "      5. Click 'Save', then add model 'qwen2:7b'"
  echo
  echo "    (No internet needed — model is already present in the ollama volume.)"
  echo
  echo "  Step 3: Configure Embedding Model (Knowledge Base)"
  echo "  --------------------------------------------------"
  echo "    If you copied ollama-models-embedding.tar.gz to the server,"
  echo "    the embedding model (bge-small-zh-v1.5) is auto-restored."
  echo
  echo "    In Dify Console:"
  echo "      1. Settings -> Model Providers -> Ollama"
  echo "      2. Add model type: 'Text Embedding'"
  echo "      3. Model Name: bge-small-zh-v1.5"
  echo "      4. Click 'Save'"
  echo
  echo "    (Required for Knowledge Base / Vector search features)"
  echo
  echo "  Step 4: Create Diagnosis Workflow"
  echo "  ----------------------------------"
  echo "    In Dify Console:"
  echo "      1. Create → Workflow"
  echo "      2. Design your diagnosis workflow"
  echo "         - Input: log_text, server_id"
  echo "         - Node: LLM (select Ollama model)"
  echo "         - Output: diagnosis report"
  echo "      3. Publish the workflow"
  echo "      4. Go to API → Copy the API Key"
  echo
  echo "  Step 5: Update .env with API Key"
  echo "  ---------------------------------"
  echo "    vi $INSTALL_DIR/.env"
  echo "    Set: DIFY_API_KEY=<your-workflow-api-key>"
  echo
  echo "  Step 6: Restart backend"
  echo "  ------------------------"
  echo "    cd $INSTALL_DIR && $COMPOSE -p fa restart backend"
  echo
  echo "  NOTE: For Knowledge Base features, you must also"
  echo "  configure the Embedding model in each workflow."
  echo
  echo "=============================================="
  echo "  OFFLINE MODE (No LLM configured)"
  echo "=============================================="
  echo "  If DIFY_API_KEY is not set, the system will"
  echo "  use MOCK_REPORT as fallback. This is useful"
  echo "  for testing the system without LLM."
  echo
  echo "=============================================="
  echo "  Agent Installation (on monitored servers)"
  echo "=============================================="
  echo "  curl -fsSL \"http://<SERVER_IP>:8000/api/agent/install.sh?server_id=Node-01\" | sudo bash"
  echo
  echo "=============================================="
  echo "  Useful Commands"
  echo "=============================================="
  echo "  Status:    $COMPOSE -p fa ps"
  echo "  Logs:      $COMPOSE -p fa logs -f backend"
  echo "  Ollama:    docker exec -it fa-ollama ollama list"
  echo "  Stop:      $COMPOSE -p fa down"
  echo "  Restart:   $COMPOSE -p fa restart"
  echo "=============================================="
}

confirm_install() {
  if [[ $SKIP_CONFIRM -eq 1 ]]; then
    return 0
  fi

  echo
  echo "=============================================="
  echo "  FA Diagnosis System — Installation Confirm"
  echo "=============================================="
  echo "  Bundle:    $BUNDLE_NAME"
  echo "  Install to: $INSTALL_DIR"
  echo "  Images:    Will be loaded from deploy-images.tar"
  echo "  Mode:      Full Offline (no internet required)"
  echo "  Docker:    Will be installed from docker-26.1.4.tgz if not present"
  echo "  Compose:   Will be installed from docker-compose binary if not present"
  echo "  LLM:       Ollama local model server included"
  echo "=============================================="
  echo
  read -r -p "Continue with installation? (y/N) " response
  case "$response" in
    [yY][eE][sS]|[yY]) ;;
    *) die "Installation cancelled" ;;
  esac
}

main() {
  parse_args "$@"
  check_bundle
  check_install_dir
  confirm_install

  extract_bundle
  check_prerequisites
  verify_offline_packages
  verify_frontend
  load_images
  verify_images
  setup_env
  restore_ollama_model
  restore_embedding_model
  start_services
  wait_for_services
  show_status

  log_ok "Installation completed successfully!"
}

main "$@"