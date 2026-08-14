#!/usr/bin/env bash
# FA Diagnosis System — Public Network One-Click Installer
# ======================================================
# Run on a server WITH internet access
# Usage: sudo bash deploy/install-public.sh [--skip-confirm]
#
# Features:
#   - Loads pre-built images from deploy-images.tar (faster)
#   - Falls back to pulling from Docker Hub if tar not found
#   - Uses external LLM API (OpenAI, Anthropic, etc.) via Dify

set -euo pipefail

INSTALL_DIR="/opt/fa"
COMPOSE_FILE="docker-compose-public.yml"

SKIP_CONFIRM=0

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log_ok() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [OK] $*"
}

log_warn() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $*" >&2
}

die() {
  log_error "$*"
  exit 1
}

log_error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --skip-confirm) SKIP_CONFIRM=1; shift ;;
      -h|--help)
        cat <<EOF
Usage: sudo bash deploy/install-public.sh [options]

FA Diagnosis System — Public Network One-Click Installer

Options:
  --skip-confirm    Skip interactive confirmation steps
  -h, --help        Show this help message

Prerequisites:
  - Docker Engine (https://docs.docker.com/engine/install/)
  - Docker Compose v2+
  - Internet access

Example:
  sudo bash deploy/install-public.sh --skip-confirm
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

  if ! command -v docker >/dev/null 2>&1; then
    die "Docker not found. Install with: sudo apt install docker.io"
  fi

  if docker compose version >/dev/null 2>&1; then
    COMPOSE="docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE="docker-compose"
  else
    die "Docker Compose not found. Install with: sudo apt install docker-compose-plugin"
  fi

  if ! docker info >/dev/null 2>&1; then
    die "Docker daemon not running. Start with: sudo systemctl start docker"
  fi

  log_ok "Docker: $(docker --version)"
  log_ok "Compose: $(${COMPOSE} version 2>/dev/null | head -1)"
}

confirm_install() {
  if [[ $SKIP_CONFIRM -eq 1 ]]; then
    return 0
  fi

  echo
  echo "=============================================="
  echo "  FA Diagnosis System — Public Install"
  echo "=============================================="
  echo "  Install to: $INSTALL_DIR"
  echo "  Mode:      Public (includes preloaded images)"
  echo "  Images:    Loaded from deploy-images.tar"
  echo "  LLM:       Uses external API via Dify"
  echo "=============================================="
  echo
  read -r -p "Continue with installation? (y/N) " response
  case "$response" in
    [yY][eE][sS]|[yY]) ;;
    *) die "Installation cancelled" ;;
  esac
}

load_images() {
  log "Loading Docker images..."

  local images_tar="$INSTALL_DIR/deploy-images.tar"
  if [[ ! -f "$images_tar" ]]; then
    log_warn "Image archive not found: $images_tar"
    log_warn "Will pull images from Docker Hub instead"
    return 0
  fi

  if ! docker load -i "$images_tar"; then
    die "Failed to load Docker images"
  fi

  log_ok "All images loaded successfully"
}

setup_env() {
  log "Setting up environment..."

  cd "$INSTALL_DIR"

  if [[ -f .env ]]; then
    log_warn ".env already exists, keeping existing configuration"
    return
  fi

  if [[ ! -f .env.example ]]; then
    die ".env.example not found"
  fi

  cp .env.example .env
  log_ok "Created .env from .env.example"
}

start_services() {
  log "Starting services..."
  $COMPOSE -f "$COMPOSE_FILE" up -d --build
  log_ok "Services started"
}

wait_for_services() {
  log "Waiting for services to be ready..."

  local max_wait=120
  local wait_interval=10
  local elapsed=0

  while [[ "$elapsed" -lt "$max_wait" ]]; do
    local backend_ready=0
    local frontend_ready=0
    local dify_ready=0

    if python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" >/dev/null 2>&1; then
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
}

show_status() {
  log "Final status check..."

  $COMPOSE -f "$COMPOSE_FILE" ps

  echo
  echo "=============================================="
  echo "  FA Diagnosis System — Installation Complete"
  echo "=============================================="
  echo
  echo "  Access URLs"
  echo "  ==========="
  echo "  FA UI (Diagnose):     http://localhost:3000"
  echo "  FA API / Health:      http://localhost:8000/health"
  echo "  FA API Docs:          http://localhost:8000/docs"
  echo "  Dify Console:         http://localhost:80"
  echo
  echo "  Default Credentials"
  echo "  ==================="
  echo "  Dify Admin:           admin / admin123456"
  echo
  echo "  Post-installation Steps"
  echo "  ======================="
  echo "  1. Open Dify Console at http://localhost:80"
  echo "     Login: admin / admin123456"
  echo
  echo "  2. Configure LLM providers in Dify:"
  echo "     Settings → Model Providers → Add OpenAI/Anthropic/etc."
  echo "     Enter your API keys"
  echo
  echo "  3. (Optional) Update .env with your own API keys:"
  echo "     vi $INSTALL_DIR/.env"
  echo
  echo "  Useful Commands"
  echo "  ==============="
  echo "  Status:    $COMPOSE -f $COMPOSE_FILE ps"
  echo "  Logs:      $COMPOSE -f $COMPOSE_FILE logs -f backend"
  echo "  Stop:      $COMPOSE -f $COMPOSE_FILE down"
  echo "  Restart:   $COMPOSE -f $COMPOSE_FILE restart"
  echo "=============================================="
}

main() {
  parse_args "$@"
  check_prerequisites
  confirm_install

  load_images
  setup_env
  start_services
  wait_for_services
  show_status

  log_ok "Installation completed successfully!"
}

main "$@"