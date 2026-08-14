#!/usr/bin/env bash
# =============================================================================
# FA/Dify 网络诊断脚本 — 排查 LLM 配置失败问题
# 服务器上执行: sudo bash deploy/diagnose-network.sh
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $*"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
info() { echo -e "  [INFO] $*"; }

echo "=============================================="
echo " FA/Dify 网络诊断"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================="

# ---------------------------------------------------------------------------
# 1. 容器状态检查
# ---------------------------------------------------------------------------
echo ""
echo "[1/5] 容器状态检查"

declare -A CONTAINERS=(
  ["dify-api"]="5001"
  ["dify-worker"]=""
  ["dify-web"]="3000"
  ["dify-nginx"]="80"
  ["fa-postgres"]="5432"
  ["fa-redis"]="6379"
  ["fa-weaviate"]="8080"
)

for name in "${!CONTAINERS[@]}"; do
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$name"; then
    pass "$name 运行中"
  else
    fail "$name 未运行"
  fi
done

# ---------------------------------------------------------------------------
# 2. Dify API 连通性
# ---------------------------------------------------------------------------
echo ""
echo "[2/5] Dify API 连通性检查"

# 2.1 nginx → api
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://localhost:80/console/api/setup 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
  pass "nginx → dify-api: HTTP $HTTP_CODE"
  curl -s http://localhost:80/console/api/setup | head -c 200
  echo ""
else
  fail "nginx → dify-api: HTTP $HTTP_CODE"

  # 直接访问 dify-api 容器
  info "尝试直接访问 dify-api:5001..."
  HTTP_DIRECT=$(docker exec dify-api curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:5001/console/api/setup 2>/dev/null || echo "000")
  if [ "$HTTP_DIRECT" = "200" ]; then
    warn "dify-api 内部正常但 nginx 代理失败 → 执行 docker exec dify-nginx nginx -s reload"
  else
    fail "dify-api 内部也返回 $HTTP_DIRECT → 查看日志: docker logs dify-api --tail 50"
  fi
fi

# 2.2 容器间 DNS 解析
echo ""
info "容器间 DNS 解析测试..."
for target in "postgres" "redis" "weaviate" "dify-web" "dify-api"; do
  if docker exec dify-api nslookup "$target" >/dev/null 2>&1 || docker exec dify-api getent hosts "$target" >/dev/null 2>&1; then
    pass "dify-api → $target DNS 解析成功"
  else
    fail "dify-api → $target DNS 解析失败"
  fi
done

# ---------------------------------------------------------------------------
# 3. 外网连通性 — 核心诊断
# ---------------------------------------------------------------------------
echo ""
echo "[3/5] 外网连通性诊断"

# 需要测试的 LLM 端点
ENDPOINTS=(
  "https://api.openai.com|443|OpenAI 官方"
  "https://api.moonshot.cn|443|Moonshot"
  "https://dashscope.aliyuncs.com|443|通义千问"
  "https://api.deepseek.com|443|DeepSeek"
  "https://api.baichuan-ai.com|443|百川"
  "https://api.zhipuai.cn|443|智谱"
  "https://open.bigmodel.cn|443|智谱2"
  "https://ark.cn-beijing.volces.com|443|火山引擎"
  "https://api.siliconflow.cn|443|SiliconFlow"
  "https://api.minimax.chat|443|MiniMax"
)

echo ""
info "宿主机 → 各 LLM API"
HOST_ANY_OK=0
for entry in "${ENDPOINTS[@]}"; do
  IFS='|' read -r url port label <<< "$entry"
  if curl -s --connect-timeout 5 "$url" >/dev/null 2>&1; then
    pass "$label: $url 可达"
    HOST_ANY_OK=1
  else
    HOST_ANY_OK=1
    warn "$label: $url 不可达 (可能需代理)"
  fi
done

if [ "$HOST_ANY_OK" -eq 0 ]; then
  echo ""
  fail "宿主机无法访问任何 LLM API — 服务器可能没有公网访问能力"
  info "检查项:"
  info "  1. 安全组出方向规则 (阿里云/腾讯云控制台)"
  info "  2. NAT 网关 / EIP 配置"
  info "  3. /etc/resolv.conf DNS 配置"
  info "  4. 防火墙: iptables -L -n | head -30"
fi

# 容器 → 外网
echo ""
info "Dify 容器 → 各 LLM API"
CONTAINER_ANY_OK=0
for entry in "${ENDPOINTS[@]}"; do
  IFS='|' read -r url port label <<< "$entry"
  if docker exec dify-api curl -s --connect-timeout 5 "$url" >/dev/null 2>&1; then
    pass "$label: $url 可达"
    CONTAINER_ANY_OK=1
  else
    warn "$label: $url 不可达"
  fi
done

if [ "$CONTAINER_ANY_OK" -eq 0 ]; then
  echo ""
  fail "Dify 容器无法访问外部 API — 可能是 Docker 网络/防火墙问题"
  info "检查: iptables -L DOCKER-USER 是否拦截转发"
fi

# DNS 解析测试
echo ""
info "DNS 解析测试..."
for domain in "api.openai.com" "dns.google" "registry-1.docker.io"; do
  if docker exec dify-api nslookup "$domain" >/dev/null 2>&1 || docker exec dify-api getent hosts "$domain" >/dev/null 2>&1; then
    pass "DNS: $domain"
  else
    fail "DNS: $domain 解析失败"
    if docker exec fa-postgres nslookup "$domain" >/dev/null 2>&1 || docker exec fa-postgres getent hosts "$domain" >/dev/null 2>&1; then
      warn "但其他容器可解析 → dify-api 容器 DNS 可能配置异常"
    fi
  fi
done

# ---------------------------------------------------------------------------
# 4. 防火墙 & 系统网络
# ---------------------------------------------------------------------------
echo ""
echo "[4/5] 系统网络与防火墙"

info "默认路由:"
ip route show default 2>/dev/null | head -1 || route -n | grep "^0.0.0.0" | head -1

info "iptables FORWARD / DOCKER-USER 规则数:"
iptables -L DOCKER-USER -n 2>/dev/null | tail -n +3 | wc -l | xargs echo "  DOCKER-USER 条数:" || warn "无法读取 iptables"

info "iptables FORWARD 默认策略:"
iptables -L FORWARD -n 2>/dev/null | head -3 || warn "无法读取"

info "Docker 网络列表:"
docker network ls --format "  {{.Name}}  {{.Driver}}  {{.Scope}}"

info "dify-api 容器 DNS 配置:"
docker exec dify-api cat /etc/resolv.conf 2>/dev/null || warn "无法读取"

info "dify-api 容器 IP 转发:"
docker exec dify-api cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo "  (无法读取)"

# ---------------------------------------------------------------------------
# 5. 修复建议
# ---------------------------------------------------------------------------
echo ""
echo "=============================================="
echo " 修复建议"
echo "=============================================="

ISSUES_FOUND=0

# 检查是否有可达端点
if [ "$CONTAINER_ANY_OK" -eq 0 ] && [ "$HOST_ANY_OK" -eq 0 ]; then
  ISSUES_FOUND=1
  echo ""
  echo "[严重] 服务器完全无法访问外网 LLM API"
  echo ""
  echo "  方案 A (推荐): 配置 HTTP 代理"
  echo "  ------------------------------"
  echo "  如果你有代理服务器 (如 clash/v2ray), 在 docker-compose.yml"
  echo "  中给 dify-api 和 dify-worker 加上环境变量:"
  echo ""
  echo "    environment:"
  echo "      HTTP_PROXY: http://宿主机IP:代理端口"
  echo "      HTTPS_PROXY: http://宿主机IP:代理端口"
  echo "      NO_PROXY: localhost,127.0.0.1,postgres,redis,weaviate,dify-web,ollama"
  echo ""
  echo "  方案 B: 使用国内中转 API"
  echo "  -------------------------"
  echo "  如 SiliconFlow (api.siliconflow.cn)、DeepSeek (api.deepseek.com)"
  echo "  如果这些也不通 → 纯网络问题，找云服务商开公网"
  echo ""
  echo "  方案 C: 用本地 Ollama 模型 (无需外网)"
  echo "  ------------------------------------"
  echo "  docker exec fa-ollama ollama pull qwen2:7b"
  echo "  Dify 配 Ollama: http://ollama:11434"
fi

# 检查 DNS
if ! docker exec dify-api nslookup "api.openai.com" >/dev/null 2>&1 && ! docker exec dify-api getent hosts "api.openai.com" >/dev/null 2>&1; then
  ISSUES_FOUND=1
  echo ""
  echo "[DNS 问题] dify-api 容器无法解析域名"
  echo "  在 docker-compose.yml 的 dify-api 下加:"
  echo "    dns:"
  echo "      - 8.8.8.8"
  echo "      - 114.114.114.114"
fi

# 检查 502
if [ "$HTTP_CODE" != "200" ] && docker exec dify-api curl -s --connect-timeout 3 http://127.0.0.1:5001/console/api/setup >/dev/null 2>&1; then
  ISSUES_FOUND=1
  echo ""
  echo "[502 问题] dify-api 正常但 nginx 502"
  echo "  docker exec dify-nginx nginx -s reload"
fi

if [ "$ISSUES_FOUND" -eq 0 ]; then
  echo ""
  echo -e "${GREEN}未发现明显问题。${NC}"
  echo "请在 Dify 控制台检查 API Key 是否正确填入。"
fi

echo ""
echo "=============================================="
echo " 诊断完成"
echo "=============================================="
