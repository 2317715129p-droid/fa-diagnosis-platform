# FA Diagnosis System — 部署文档

## 目录

1. [部署环境要求](#1-部署环境要求)
2. [版本选择](#2-版本选择)
3. [离线版本部署（无网络环境）](#3-离线版本部署无网络环境)
4. [公网版本部署（有网络环境）](#4-公网版本部署有网络环境)
5. [配置参数说明](#5-配置参数说明)
6. [常见问题处理](#6-常见问题处理)
7. [验证部署成功](#7-验证部署成功)
8. [服务管理命令](#8-服务管理命令)

---

## 1. 部署环境要求

### 硬件要求

| 配置项 | 最低配置 | 推荐配置 |
|--------|----------|----------|
| CPU | 4核 | 8核 |
| 内存 | 16GB | 32GB |
| 磁盘 | 60GB | 100GB+ |
| 网络 | - | 100Mbps+ |

### 软件要求

| 软件 | 版本要求 | 说明 |
|------|----------|------|
| Linux | CentOS 7+/Ubuntu 18.04+ | 推荐 Ubuntu 22.04 LTS |
| Docker | 20.10+ | 离线版包含 Docker 安装包 |
| Docker Compose | v2+ | 离线版包含二进制文件 |
| bash | 4.0+ | 部署脚本依赖 |
| tar/gzip | - | 解压压缩包 |

---

## 2. 版本选择

| 版本 | 文件 | 适用场景 | 特点 |
|------|------|----------|------|
| 离线版 | `fa-diagnosis-offline.tar.gz` | 内网服务器（无网络） | 包含所有镜像、依赖包、Docker安装包 |
| 公网版 | `fa-diagnosis-public.tar.gz` | 公网服务器（有网络） | 基础文件，依赖在线拉取 |
| 模型包 | `ollama-models-qwen2-7b.tar.gz` | 离线版配套 | 预下载的 Qwen2:7b 模型 |

---

## 3. 离线版本部署（无网络环境）

### 3.1 准备工作

在有网络的机器上执行以下操作：

```bash
# 1. 下载项目源码
git clone <repository-url>
cd idex

# 2. 生成离线包（需要 Docker + Node.js + Python）
bash deploy/offline-prep.sh

# 3. 导出 Ollama 模型（如果已下载模型）
docker run --rm -v ollama_models:/data -v $(pwd):/backup alpine tar -czhf /backup/ollama-models-qwen2-7b.tar.gz -C /data .

# 4. 将以下文件复制到目标内网服务器
#    - fa-diagnosis-offline.tar.gz
#    - ollama-models-qwen2-7b.tar.gz（可选，用于预加载模型）
```

### 3.2 一键安装（推荐）

```bash
# 1. 将压缩包复制到目标服务器
# 2. 创建安装目录并解压
mkdir -p /opt/fa
tar -xzf fa-diagnosis-offline.tar.gz -C /opt/fa
cd /opt/fa

# 3. 执行一键安装脚本
sudo bash deploy/install.sh --skip-confirm
```

**安装脚本会自动完成：**
- 检查/安装 Docker（从离线包）
- 检查/安装 Docker Compose（从离线包）
- 加载所有 Docker 镜像
- 验证离线 Python 依赖包
- 验证前端构建产物
- 配置环境变量（自动创建 .env）
- 启动所有服务

### 3.3 手动安装（高级用户）

```bash
# 1. 解压压缩包
mkdir -p /opt/fa
tar -xzf fa-diagnosis-offline.tar.gz -C /opt/fa
cd /opt/fa

# 2. 安装 Docker（如果未安装）
tar -xzf docker-26.1.4.tgz -C /tmp/
cp -f /tmp/docker/* /usr/local/bin/
chmod +x /usr/local/bin/docker* /usr/local/bin/runc /usr/local/bin/containerd*

# 3. 安装 Docker Compose（如果未安装）
cp -f docker-compose-bin /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# 4. 启动 Docker 服务
systemctl daemon-reload
systemctl start containerd
systemctl start docker

# 5. 加载 Docker 镜像
docker load -i deploy-images.tar

# 6. 配置环境变量
cp .env.offline.example .env
# 编辑 .env 文件，设置 DIFY_API_KEY 等配置

# 7. 启动服务
docker compose -p fa up -d --build
```

### 3.4 离线环境配置步骤

安装完成后，需要完成以下配置：

```bash
# Step 1: 登录 Dify 控制台
# 访问: http://<服务器IP>:80
# 账号: admin / admin123456

# Step 2: 导入预加载的 Ollama 模型（如果有）
docker run --rm -v fa_ollama_models:/data -v /path/to/model:/backup alpine tar -xzhf /backup/ollama-models-qwen2-7b.tar.gz -C /data
docker compose -p fa restart ollama
docker exec -it fa-ollama ollama list

# Step 3: 配置 Ollama 模型提供者
# 在 Dify 控制台: Settings → Model Providers → Ollama
# 设置 API Base URL: http://ollama:11434

# Step 4: 创建诊断工作流并获取 API Key
# 在 Dify 控制台: Create → Workflow

# Step 5: 更新 .env 配置
vi /opt/fa/.env
# 设置: DIFY_API_KEY=<你的工作流API Key>

# Step 6: 重启后端服务
docker compose -p fa restart backend
```

---

## 4. 公网版本部署（有网络环境）

### 4.1 一键安装

```bash
# 1. 将压缩包复制到目标服务器
# 2. 创建安装目录并解压
mkdir -p /opt/fa
tar -xzf fa-diagnosis-public.tar.gz -C /opt/fa
cd /opt/fa

# 3. 执行一键安装脚本（需要 Docker 已安装）
sudo bash deploy/install-public.sh --skip-confirm
```

### 4.2 手动安装

```bash
# 1. 解压压缩包
mkdir -p /opt/fa
tar -xzf fa-diagnosis-public.tar.gz -C /opt/fa
cd /opt/fa

# 2. 加载预存镜像（可选，加速部署）
docker load -i deploy-images.tar

# 3. 配置环境变量
cp .env.example .env
# 编辑 .env 文件，设置 DIFY_API_KEY 等配置

# 4. 启动服务（使用公网版配置）
docker compose -f docker-compose-public.yml -p fa up -d --build
```

### 4.3 公网环境配置步骤

```bash
# Step 1: 登录 Dify 控制台
# 访问: http://<服务器IP>:80
# 账号: admin / admin123456

# Step 2: 配置 LLM 提供者（如 OpenAI）
# 在 Dify 控制台: Settings → Model Providers
# 添加 OpenAI/Anthropic 等，输入 API Key

# Step 3: 创建诊断工作流并获取 API Key

# Step 4: 更新 .env 配置
vi /opt/fa/.env
# 设置: DIFY_API_KEY=<你的工作流API Key>

# Step 5: 重启后端服务
docker compose -f docker-compose-public.yml -p fa restart backend
```

---

## 5. 配置参数说明

### 5.1 核心配置（.env 文件）

| 参数 | 默认值 | 说明 |
|------|--------|------|
| DIFY_API_URL | http://dify-nginx:80 | Dify API 地址（Docker 内部使用服务名） |
| DIFY_API_KEY | 空 | 诊断工作流的 API Key |
| DIFY_TRANSLATE_API_KEY | 空 | 翻译工作流的 API Key（可选） |
| DATABASE_URL | sqlite:///data/fa_data.db | 数据库连接地址 |
| DIFY_SECRET_KEY | sk-fa-dify-change-me-in-production | Dify 加密密钥 |
| DIFY_INIT_PASSWORD | admin123456 | Dify 管理员初始密码 |

### 5.2 Dify 配置

| 参数 | 默认值 | 说明 |
|------|--------|------|
| POSTGRES_USER | postgres | PostgreSQL 用户名 |
| POSTGRES_PASSWORD | difyai123456 | PostgreSQL 密码 |
| POSTGRES_DB | dify | PostgreSQL 数据库名 |
| REDIS_PASSWORD | difyai123456 | Redis 密码 |
| WEAVIATE_API_KEY | WVF5YThaHlkYjkNmNTM | Weaviate API Key |

### 5.3 本地 LLM 配置（仅离线版）

| 参数 | 默认值 | 说明 |
|------|--------|------|
| OLLAMA_HOST | http://ollama:11434 | Ollama 服务地址 |
| OLLAMA_PORT | 11434 | Ollama 服务端口 |

---

## 6. 常见问题处理

### 6.1 Docker 相关问题

**问题：Docker daemon 未启动**
```bash
systemctl start containerd
systemctl start docker
```

**问题：Docker 权限不足**
```bash
sudo usermod -aG docker $USER
newgrp docker
```

**问题：离线包解压后 Docker 命令不存在**
```bash
# 从离线包安装 Docker
tar -xzf docker-26.1.4.tgz -C /tmp/
cp -f /tmp/docker/* /usr/local/bin/
chmod +x /usr/local/bin/docker*
```

### 6.2 服务启动问题

**问题：backend 服务启动失败**
```bash
# 查看日志
docker compose -p fa logs -f backend

# 常见原因：
# 1. DIFY_API_KEY 未设置（可留空使用 mock 模式）
# 2. 数据库目录权限问题
# 3. 端口被占用
```

**问题：frontend 服务无法访问**
```bash
# 检查 nginx 配置
docker exec -it fa-frontend cat /etc/nginx/conf.d/default.conf

# 检查端口映射
docker compose -p fa ps
```

**问题：Dify 控制台无法访问**
```bash
# 检查 Dify 服务状态
docker compose -p fa ps | grep dify

# 查看 Dify API 日志
docker compose -p fa logs -f dify-api
```

### 6.3 网络问题

**问题：容器间无法通信**
```bash
# 检查网络配置
docker network ls
docker network inspect fa_fa_network

# 确保所有服务都在同一网络
docker compose -p fa up -d
```

**问题：离线环境无法安装 Python 依赖**
```bash
# 确保 offline-packages 目录存在且包含 .whl 文件
ls /opt/fa/offline-packages/

# 如果为空，需要在有网络的机器上重新生成离线包
```

### 6.4 模型相关问题

**问题：Ollama 模型未加载**
```bash
# 导入模型（离线方式）
docker run --rm -v fa_ollama_models:/data -v /path/to/model:/backup alpine tar -xzhf /backup/ollama-models-qwen2-7b.tar.gz -C /data
docker compose -p fa restart ollama

# 或在线拉取（需要网络）
docker exec -it fa-ollama ollama pull qwen2:7b
```

**问题：Dify 连接 Ollama 失败**
```bash
# 在 Dify 控制台配置 Ollama 时使用内部地址
# API Base URL: http://ollama:11434

# 测试连接
docker exec -it fa-dify-api curl http://ollama:11434/api/tags
```

---

## 7. 验证部署成功

### 7.1 服务状态检查

```bash
# 查看所有服务状态
docker compose -p fa ps

# 期望状态：所有服务都是 "Up (healthy)" 或 "Up"
```

### 7.2 健康检查

```bash
# 检查 FA Backend
curl http://localhost:8000/health
# 期望返回: {"status": "ok"}

# 检查 FA Frontend
curl http://localhost:3000
# 期望返回: HTML 页面内容

# 检查 Dify Console
curl http://localhost:80
# 期望返回: Dify 登录页面

# 检查 Ollama（仅离线版）
curl http://localhost:11434/api/tags
# 期望返回: 模型列表
```

### 7.3 功能验证

```bash
# 验证诊断 API
curl -X POST http://localhost:8000/api/diagnose \
  -H "Content-Type: application/json" \
  -d '{"log_text": "test log", "server_id": "test-server"}'

# 如果 DIFY_API_KEY 未设置，会返回 mock 报告
```

---

## 8. 服务管理命令

### 8.1 基础命令

```bash
# 启动服务
docker compose -p fa up -d

# 停止服务
docker compose -p fa down

# 重启服务
docker compose -p fa restart

# 查看服务状态
docker compose -p fa ps

# 查看日志
docker compose -p fa logs -f
docker compose -p fa logs -f backend
docker compose -p fa logs -f frontend
docker compose -p fa logs -f dify-api
```

### 8.2 数据管理

```bash
# 备份 PostgreSQL（Dify 数据）
docker exec fa-postgres pg_dump -U postgres dify > backup.sql

# 备份 SQLite（FA 数据）
docker cp fa-backend:/app/data/fa_data.db ./fa_data.db.backup

# 备份 Ollama 模型（仅离线版）
docker run --rm -v fa_ollama_models:/data -v $(pwd):/backup alpine tar -czhf /backup/ollama-models-backup.tar.gz -C /data .
```

### 8.3 更新部署

```bash
# 停止服务
docker compose -p fa down

# 更新代码（解压新的压缩包）
rm -rf /opt/fa/*
tar -xzf fa-diagnosis-offline.tar.gz -C /opt/fa

# 更新环境变量（如果有变更）
cp .env.offline.example .env

# 重新启动
docker compose -p fa up -d --build
```

---

## 附录：服务端口汇总

| 服务 | 端口 | 说明 |
|------|------|------|
| FA Frontend | 3000 | 诊断系统前端 |
| FA Backend | 8000 | 诊断系统后端 API |
| Dify Console | 80 | Dify 控制台 |
| Ollama | 11434 | 本地大模型服务（仅离线版） |
| PostgreSQL | 5432 | 数据库（内部使用） |
| Redis | 6379 | 缓存（内部使用） |
| Weaviate | 8080 | 向量数据库（内部使用） |

---

**文档版本**: v1.0  
**最后更新**: 2026-07-23  
**适用项目**: FA Diagnosis System