#!/bin/bash
# FA Diagnosis Agent installer for Linux servers.
# Usage:
#   sudo bash agent-install.sh --server-id Node-01 --center http://10.0.0.1:8000/api/collect

set -euo pipefail

SERVER_ID=""
CENTER_URL=""

AGENT_DIR="/opt/fa-agent"
LOG_DIR="/var/log/fa-agent"
COLLECTOR_DST="${AGENT_DIR}/collector.py"
SERVICE_FILE="/etc/systemd/system/fa-collector.service"
TIMER_FILE="/etc/systemd/system/fa-collector.timer"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTOR_SRC="${SCRIPT_DIR}/collector.py"

usage() {
  cat <<EOF
Usage: sudo $0 --server-id <ID> --center <URL>

Required arguments:
  --server-id   Server identifier (e.g. Node-01)
  --center      Central FastAPI collect URL
                (e.g. http://10.0.0.1:8000/api/collect)

Example:
  sudo bash $0 --server-id Node-01 --center http://10.0.0.1:8000/api/collect
EOF
}

log() {
  echo "[fa-agent-install] $*"
}

die() {
  echo "[fa-agent-install] ERROR: $*" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --server-id)
      [[ $# -ge 2 ]] || die "--server-id requires a value"
      SERVER_ID="$2"
      shift 2
      ;;
    --center)
      [[ $# -ge 2 ]] || die "--center requires a value"
      CENTER_URL="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$SERVER_ID" ]] || die "--server-id is required"
[[ -n "$CENTER_URL" ]] || die "--center is required"
[[ "$(id -u)" -eq 0 ]] || die "please run as root (sudo)"
[[ -f "$COLLECTOR_SRC" ]] || die "collector.py not found next to installer: $COLLECTOR_SRC"

log "server-id=${SERVER_ID}"
log "center=${CENTER_URL}"

# ---------------------------------------------------------------------------
# Dependencies: Python 3.6+, ipmitool, requests
# ---------------------------------------------------------------------------
detect_pkg_mgr() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt"
  elif command -v yum >/dev/null 2>&1; then
    echo "yum"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  else
    echo ""
  fi
}

PKG_MGR="$(detect_pkg_mgr)"

ensure_python() {
  if command -v python3 >/dev/null 2>&1; then
    local ver
    ver="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
    python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 6) else 1)' \
      || die "Python 3.6+ required, found ${ver}"
    log "Python ${ver} OK"
    return
  fi

  log "Python 3 not found; installing..."
  case "$PKG_MGR" in
    apt) apt-get update -y && apt-get install -y python3 python3-pip ;;
    yum) yum install -y python3 python3-pip ;;
    dnf) dnf install -y python3 python3-pip ;;
    *) die "no apt-get/yum/dnf found; install Python 3.6+ manually" ;;
  esac
}

ensure_ipmitool() {
  if command -v ipmitool >/dev/null 2>&1; then
    log "ipmitool OK"
    return
  fi
  log "ipmitool not found; installing..."
  case "$PKG_MGR" in
    apt) apt-get update -y && apt-get install -y ipmitool ;;
    yum) yum install -y OpenIPMI ipmitool ;;
    dnf) dnf install -y OpenIPMI ipmitool ;;
    *) die "no apt-get/yum/dnf found; install ipmitool manually" ;;
  esac
}

ensure_requests() {
  if python3 -c "import requests" >/dev/null 2>&1; then
    log "python requests OK"
    return
  fi
  log "installing requests via pip..."
  if command -v pip3 >/dev/null 2>&1; then
    pip3 install --upgrade requests
  else
    case "$PKG_MGR" in
      apt) apt-get install -y python3-pip && pip3 install --upgrade requests ;;
      yum) yum install -y python3-pip && pip3 install --upgrade requests ;;
      dnf) dnf install -y python3-pip && pip3 install --upgrade requests ;;
      *) die "pip3 not available; install python3-requests manually" ;;
    esac
  fi
  python3 -c "import requests" || die "failed to import requests after install"
}

ensure_python
ensure_ipmitool
ensure_requests

# Optional but used by collector
if ! command -v dmidecode >/dev/null 2>&1; then
  log "dmidecode not found; attempting install..."
  case "$PKG_MGR" in
    apt) apt-get install -y dmidecode || true ;;
    yum) yum install -y dmidecode || true ;;
    dnf) dnf install -y dmidecode || true ;;
  esac
fi

# ---------------------------------------------------------------------------
# Directories
# ---------------------------------------------------------------------------
mkdir -p "$AGENT_DIR" "$LOG_DIR"
chmod 755 "$AGENT_DIR" "$LOG_DIR"
log "created ${AGENT_DIR} and ${LOG_DIR}"

# ---------------------------------------------------------------------------
# Install collector and inject config
# ---------------------------------------------------------------------------
cp -f "$COLLECTOR_SRC" "$COLLECTOR_DST"
chmod 755 "$COLLECTOR_DST"

# Escape sed replacement specials: \ & and delimiter |
escape_sed() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

ESC_SERVER_ID="$(escape_sed "$SERVER_ID")"
ESC_CENTER_URL="$(escape_sed "$CENTER_URL")"

sed -i \
  -e "s|^SERVER_ID = \".*\"|SERVER_ID = \"${ESC_SERVER_ID}\"|" \
  -e "s|^CENTER_URL = \".*\"|CENTER_URL = \"${ESC_CENTER_URL}\"|" \
  "$COLLECTOR_DST"

grep -q "SERVER_ID = \"${SERVER_ID}\"" "$COLLECTOR_DST" \
  || die "failed to inject SERVER_ID into collector.py"
grep -q "CENTER_URL = \"${CENTER_URL}\"" "$COLLECTOR_DST" \
  || die "failed to inject CENTER_URL into collector.py"

log "installed collector -> ${COLLECTOR_DST}"

# ---------------------------------------------------------------------------
# systemd service
# ---------------------------------------------------------------------------
cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=FA Diagnosis Agent
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/fa-agent/collector.py
Restart=always
RestartSec=10
StandardOutput=append:/var/log/fa-agent/collector.log
StandardError=append:/var/log/fa-agent/collector.log

[Install]
WantedBy=multi-user.target
EOF

# ---------------------------------------------------------------------------
# systemd timer
# ---------------------------------------------------------------------------
cat > "$TIMER_FILE" <<'EOF'
[Unit]
Description=FA Diagnosis Agent Timer

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
EOF

log "wrote ${SERVICE_FILE}"
log "wrote ${TIMER_FILE}"

# ---------------------------------------------------------------------------
# Enable and start
# ---------------------------------------------------------------------------
systemctl daemon-reload
systemctl enable fa-collector.timer
systemctl start fa-collector.timer

echo
echo "=============================================="
echo "  FA Diagnosis Agent installed successfully"
echo "=============================================="
echo "  SERVER_ID : ${SERVER_ID}"
echo "  CENTER    : ${CENTER_URL}"
echo "  Script    : ${COLLECTOR_DST}"
echo "  Logs      : ${LOG_DIR}/collector.log"
echo
echo "  Check status:"
echo "    systemctl status fa-collector.timer"
echo "    systemctl list-timers fa-collector.timer"
echo "    journalctl -u fa-collector.service -f"
echo "=============================================="
