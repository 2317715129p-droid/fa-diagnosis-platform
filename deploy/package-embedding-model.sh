#!/usr/bin/env bash
# ============================================================
# FA 诊断系统 — Embedding 模型离线包生成器
# 用途: 在内网/离线部署里让 Dify 知识库可用(向量化需要 embedding 模型)
# 用法:
#   bash package-embedding-model.sh [模型名] [输出路径]
#   模型名默认 nomic-embed-text(英文通用, 最小 ~274MB, Dify 兼容最好)
#   中文知识库推荐:
#     bge-small-zh-v1.5   小, 中文优化, ~130MB   <-- 8GB 机器首选
#     bge-m3              更强, 多语言,    ~2.3GB
# 前置: 本机已装 Ollama 且能联网(仅用于一次性 pull)
# 产出: ollama-models-embedding.tar.gz (放到服务器 /opt/fa/ 即可被离线部署识别)
# ============================================================
set -euo pipefail

MODEL="${1:-nomic-embed-text}"
OUT="${2:-ollama-models-embedding.tar.gz}"

# 定位 Ollama 模型根目录(~/.ollama)
if [ -n "${OLLAMA_MODELS:-}" ]; then
  ODIR="$OLLAMA_MODELS"
elif [ -d "$HOME/.ollama/models" ]; then
  ODIR="$HOME/.ollama"
elif command -v cygpath >/dev/null 2>&1 && [ -d "$(cygpath "$USERPROFILE/.ollama")/models" ]; then
  ODIR="$(cygpath "$USERPROFILE/.ollama")"
else
  echo "找不到 Ollama 模型目录, 请确认 Ollama 已安装并能运行" >&2
  exit 1
fi

echo "模型: $MODEL"
echo "Ollama 目录: $ODIR"

ollama pull "$MODEL"

echo "打包 -> $OUT"
tar -czf "$OUT" -C "$ODIR" models id_ed25519 id_ed25519.pub

echo "完成: $OUT ($(du -h "$OUT" | cut -f1))"
echo "把它和主包一起拷到服务器 /opt/fa/, 离线部署会自动恢复;"
echo "或手动恢复: docker run --rm -v fa_ollama_models:/data -v \$PWD:/backup alpine tar -xzf /backup/$OUT -C /data"
