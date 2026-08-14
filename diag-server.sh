#!/usr/bin/env bash
# =============================================================
# FA 诊断系统 - 公网部署排错脚本 (在阿里云服务器上运行)
# 用法:
#   cd /path/to/fa-project
#   bash diag-server.sh
# 把整段输出复制发给我即可。
# =============================================================
set +e
HR="============================================================"

echo "$HR"
echo "【1】容器状态 (docker compose ps)"
echo "$HR"
docker compose ps 2>/dev/null || docker-compose ps 2>/dev/null || docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

echo
echo "$HR"
echo "【2】监听端口 (确认 3000 前端 / 8000 后端 是否在听)"
echo "$HR"
( command -v ss >/dev/null && ss -ltnp 2>/dev/null | grep -E ':3000|:8000|:80 ' ) \
  || ( command -v netstat >/dev/null && netstat -ltnp 2>/dev/null | grep -E ':3000|:8000|:80 ' ) \
  || echo "(ss/netstat 不可用,跳过)"

echo
echo "$HR"
echo "【3】前端页面能否打开 (从服务器本机访问 3000)"
echo "$HR"
echo "--- curl http://localhost:3000/ (看 <title>) ---"
curl -s --max-time 5 http://localhost:3000/ | grep -iE '<title>|root|FA' | head -5 || echo "!! 3000 端口无响应"

echo
echo "$HR"
echo "【4】后端健康 & API (本机直连 8000)"
echo "$HR"
echo "--- /health ---"
curl -s --max-time 5 http://localhost:8000/health; echo
echo "--- /api/assets ---"
curl -s --max-time 5 -o /dev/null -w "HTTP %{http_code}\n" http://localhost:8000/api/assets
curl -s --max-time 5 http://localhost:8000/api/assets | head -c 300; echo

echo
echo "$HR"
echo "【5】关键: 经前端 nginx 代理的 /api 是否通 (这是浏览器实际走的路径)"
echo "$HR"
echo "--- http://localhost:3000/api/assets ---"
curl -s --max-time 5 -o /dev/null -w "HTTP %{http_code}\n" http://localhost:3000/api/assets
curl -s --max-time 5 http://localhost:3000/api/assets | head -c 300; echo

echo
echo "$HR"
echo "【6】WebSocket 代理探测 (nginx /ws -> backend)"
echo "$HR"
curl -s --max-time 5 -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
     -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
     http://localhost:3000/ws/diagnose | head -c 400; echo

echo
echo "$HR"
echo "【7】后端容器日志尾部 (看有没有抛错)"
echo "$HR"
docker logs --tail 40 fa-backend 2>&1 || echo "(容器名 fa-backend 不存在, 用 docker ps 看实际名字)"

echo
echo "$HR"
echo "【8】前端容器日志尾部"
echo "$HR"
docker logs --tail 25 fa-frontend 2>&1 || echo "(容器名 fa-frontend 不存在)"

echo
echo "$HR"
echo "【9】公网可达性提示"
echo "$HR"
PUB=$(curl -s --max-time 5 http://ifconfig.me 2>/dev/null || curl -s --max-time 5 http://api.ipify.org 2>/dev/null)
echo "服务器探测到的公网 IP: ${PUB:-未知}"
echo ">>> 请在阿里云 ECS【安全组】确认已放行: 入方向 TCP 3000 (前端), 以及 80/443 (若有反代)"
echo "$HR"
echo "诊断结束。请把以上全部输出复制发我。"
