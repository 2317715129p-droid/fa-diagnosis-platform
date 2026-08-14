# FA Diagnosis — offline pack (Windows PowerShell)
# Updated for Dify 1.15.0 + Ollama 0.5.7
# Run in:  D:\idex
# Requires: Docker Desktop running, Node.js, Python/pip
# Usage:   powershell -ExecutionPolicy Bypass -File .\deploy\offline-prep.ps1

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)
$Root = Get-Location
Write-Host "=============================================="
Write-Host "  FA Diagnosis — offline prep (Dify 1.15.0)"
Write-Host "  Working dir: $Root"
Write-Host "=============================================="

# Keep in sync with docker-compose.yml
$BaseImages = @(
  "python:3.11-slim",
  "nginx:1.27-alpine",
  "busybox:1.36.1",
  "langgenius/dify-sandbox:0.2.15",
  "ubuntu/squid:latest",
  "postgres:15-alpine",
  "redis:6-alpine",
  "semitechnologies/weaviate:1.27.0",
  "ollama/ollama:0.5.7"
)

$DifyImages = @(
  "langgenius/dify-api:1.15.0",
  "langgenius/dify-web:1.15.0",
  "langgenius/dify-plugin-daemon:0.6.3-local"
)

$AllImages = $BaseImages + $DifyImages

function Need($cmd) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    throw "Required command not found: $cmd"
  }
}

Need docker
Need npm
Need pip
Need tar

# ---------------------------------------------------------------------------
# 0) Clean previous outputs
# ---------------------------------------------------------------------------
Write-Host "`n[0/6] Cleaning old outputs..."
@(
  "deploy-images.tar",
  "fa-backend.tar",
  "fa-diagnosis-offline.tar.gz"
) | ForEach-Object {
  if (Test-Path $_) { Remove-Item -Force $_; Write-Host "  removed $_" }
}
if (Test-Path "dist") { Remove-Item -Recurse -Force "dist"; Write-Host "  removed dist" }
if (Test-Path "offline-packages") {
  Get-ChildItem "offline-packages" -File | Remove-Item -Force
  Write-Host "  cleared offline-packages"
} else {
  New-Item -ItemType Directory -Path "offline-packages" | Out-Null
}

# ---------------------------------------------------------------------------
# 1) Pull all images
# ---------------------------------------------------------------------------
Write-Host "`n[1/6] Pulling Docker images (needs internet + Docker Desktop)..."
foreach ($img in $AllImages) {
  Write-Host "  -> docker pull $img"
  docker pull $img
  if ($LASTEXITCODE -ne 0) { throw "docker pull failed: $img" }
}

# ---------------------------------------------------------------------------
# 2) Save images
# ---------------------------------------------------------------------------
Write-Host "`n[2/6] Saving images to deploy-images.tar ..."
docker save -o deploy-images.tar @AllImages
if ($LASTEXITCODE -ne 0) { throw "docker save failed" }
Get-Item deploy-images.tar | Format-List Name, Length

# ---------------------------------------------------------------------------
# 3) Build & save fa-backend image
# ---------------------------------------------------------------------------
Write-Host "`n[3/6] Building & saving fa-backend:1.0.0 ..."
$tmpBuild = Join-Path ([System.IO.Path]::GetTempPath()) "fa-backend-build"
if (Test-Path $tmpBuild) { Remove-Item -Recurse -Force $tmpBuild }
New-Item -ItemType Directory -Path $tmpBuild | Out-Null

Copy-Item "backend\Dockerfile" "$tmpBuild\Dockerfile"
Copy-Item "backend\requirements.txt" "$tmpBuild\requirements.txt"
Copy-Item -Recurse "offline-packages" "$tmpBuild\offline-packages"
Copy-Item "main.py", "config.py" "$tmpBuild\"
Copy-Item -Recurse "api", "models", "services", "src" "$tmpBuild\"

docker build -t fa-backend:1.0.0 -f "$tmpBuild\Dockerfile" $tmpBuild
if ($LASTEXITCODE -ne 0) { throw "docker build fa-backend failed" }

docker save -o fa-backend.tar fa-backend:1.0.0
if ($LASTEXITCODE -ne 0) { throw "docker save fa-backend failed" }

Remove-Item -Recurse -Force $tmpBuild
Get-Item fa-backend.tar | Format-List Name, Length

# ---------------------------------------------------------------------------
# 4) pip download (Linux wheels for python:3.11-slim)
# ---------------------------------------------------------------------------
Write-Host "`n[4/6] Downloading Python wheels into offline-packages/ ..."
$Req = if (Test-Path "backend\requirements.txt") { "backend\requirements.txt" } else { "requirements.txt" }

$pipOk = $true
pip download -r $Req -d offline-packages `
  --python-version 311 `
  --platform manylinux2014_x86_64 `
  --implementation cp `
  --abi cp311 `
  --only-binary=:all:
if ($LASTEXITCODE -ne 0) {
  Write-Host "WARN: binary-only download failed; falling back to host wheels"
  pip download -r $Req -d offline-packages
  if ($LASTEXITCODE -ne 0) { throw "pip download failed" }
  $pipOk = $false
}
# Sync requirements
$reqFull = (Resolve-Path $Req).Path
$backendReq = Join-Path $Root "backend\requirements.txt"
$rootReq = Join-Path $Root "requirements.txt"
if ($reqFull -ne (Resolve-Path $backendReq -ErrorAction SilentlyContinue).Path) {
  Copy-Item $Req $backendReq -Force
}
if ($reqFull -ne (Resolve-Path $rootReq -ErrorAction SilentlyContinue).Path) {
  Copy-Item $Req $rootReq -Force
}
$pkgCount = (Get-ChildItem offline-packages -File).Count
Write-Host "  packages: $pkgCount  (linux-wheels=$pipOk)"

# ---------------------------------------------------------------------------
# 5) Frontend build
# ---------------------------------------------------------------------------
Write-Host "`n[5/6] Building frontend dist/ ..."
Get-Process -Name "node","esbuild" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

if (-not (Test-Path "node_modules")) {
  Write-Host "  npm install ..."
  npm install
  if ($LASTEXITCODE -ne 0) { throw "npm install failed" }
}

npm run build
if ($LASTEXITCODE -ne 0) { throw "npm run build failed" }
if (-not (Test-Path "dist")) { throw "dist/ missing after build" }
Write-Host "  dist OK"

# ---------------------------------------------------------------------------
# 6) Pack tarball
# ---------------------------------------------------------------------------
Write-Host "`n[6/6] Creating fa-diagnosis-offline.tar.gz ..."
$Out = "fa-diagnosis-offline.tar.gz"
$paths = @(
  "deploy-images.tar",
  "fa-backend.tar",
  "offline-packages",
  "dist",
  "backend",
  "frontend",
  "dify",
  "ssrf_proxy",
  "volumes",
  "deploy",
  "docker-compose.yml",
  ".env.example",
  ".env.offline.example",
  ".dockerignore",
  "requirements.txt",
  "main.py",
  "config.py",
  "api",
  "models",
  "services",
  "src",
  "static",
  "package.json",
  "package-lock.json",
  "index.html",
  "vite.config.js",
  "docker-26.1.4.tgz",
  "docker-compose-bin"
) | Where-Object { Test-Path $_ }

tar -czf $Out @paths
if ($LASTEXITCODE -ne 0) { throw "tar failed" }

Get-Item $Out | Format-List FullName, Length
Write-Host "=============================================="
Write-Host "  Done"
Write-Host "=============================================="
Write-Host "  Bundle: $Root\$Out"
Write-Host ""
Write-Host "  Copy these files to the target server:"
Write-Host "    1. fa-diagnosis-offline.tar.gz (main install)"
Write-Host "    2. ollama-models-qwen2-7b.tar.gz (LLM model, optional)"
Write-Host ""
Write-Host "  On intranet server:"
Write-Host "    # Extract and install:"
Write-Host "    mkdir -p /opt/fa"
Write-Host "    tar -xzf fa-diagnosis-offline.tar.gz -C /opt/fa"
Write-Host "    cd /opt/fa && sudo bash deploy/install.sh --skip-confirm"
Write-Host "=============================================="
