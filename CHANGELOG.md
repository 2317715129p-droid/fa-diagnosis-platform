# FA 诊断系统 — 开发与部署日志

## 概述
本文档记录了 FA 诊断系统从开发到部署准备过程中的所有变更、修改和决策。

---

## 版本历史

### v1.0.0 - 初始开发
**日期:** 2026-07-21 之前

- ✅ 核心后端 API 开发 (FastAPI)
- ✅ 前端 UI 开发 (React + Vite)
- ✅ 数据库模型 (SQLite)
- ✅ Dify 工作流集成
- ✅ 日志脱敏和报告验证服务
- ✅ Agent 部署脚本

---

### v1.1.0 - 离线部署准备
**日期:** 2026-07-21

#### 任务1: 初始离线包检查
- **目标:** 验证 tar.gz 压缩包是否支持离线安装
- **行动:**
  - 审查现有的 `fa-diagnosis-offline.tar.gz` 结构
  - 检查 Docker 镜像、Python 依赖包和前端构建产物
- **发现:**
  - ✅ 包结构完整
  - ❌ 缺少"一键安装"脚本
  - ❌ `backend/Dockerfile` 缺少 `--no-index` 参数（离线环境下会失败）

#### 任务2: 创建一键安装脚本
- **目标:** 创建 `deploy/install.sh` 实现自动化离线安装
- **行动:**
  - 创建完整的安装脚本，包含：
    - 环境检查（Docker、Docker Compose、tar、gzip）
    - 压缩包完整性验证
    - 自动解压到 `/opt/fa`
    - 从 `deploy-images.tar` 加载 Docker 镜像
    - 镜像验证（7个核心镜像）
    - 从 `.env.example` 创建环境配置
    - 服务启动和健康检查
    - 显示访问 URL 和状态信息

#### 任务3: 修复 Dockerfile 离线安装
- **目标:** 确保后端在无网络环境下正常构建
- **行动:**
  - 修改 `backend/Dockerfile` 第12行：
    - 修改前: `pip install --no-cache-dir --find-links=/offline-packages -r requirements.txt`
    - 修改后: `pip install --no-cache-dir --no-index --find-links=/offline-packages -r requirements.txt`
  - 添加 `--no-index` 参数防止 pip 访问 PyPI

#### 任务4: 更新离线准备脚本
- **目标:** 将新安装脚本包含到打包中
- **行动:**
  - 更新 `deploy/offline-prep.sh`
  - 更新 `deploy/offline-prep.ps1`
  - 重新生成 `fa-diagnosis-offline.tar.gz` (~927MB → ~971MB)

---

### v1.2.0 - 本地大模型集成 (Ollama)
**日期:** 2026-07-22

#### 任务1: 添加 Ollama 服务到 Docker Compose
- **目标:** 集成本地大模型服务用于内网部署
- **行动:**
  - 在 `docker-compose.yml` 中添加 `ollama` 服务：
    - 镜像: `ollama/ollama:0.1.60`
    - 端口: `11434`
    - 数据卷: `ollama_models`
  - 更新 `offline-prep.sh` 和 `offline-prep.ps1` 拉取 Ollama 镜像

#### 任务2: 更新环境配置
- **目标:** 添加本地大模型配置项
- **行动:**
  - 更新 `.env.example` 添加 Ollama 设置：
    - `OLLAMA_HOST=http://ollama:11434`
    - `OLLAMA_PORT=11434`

#### 任务3: 更新部署脚本
- **目标:** 将 Ollama 纳入安装流程
- **行动:**
  - 更新 `deploy/install.sh` 添加 Ollama 模型导入说明
  - 更新 `deploy/start.sh` 添加内网部署说明

---

### v1.3.0 - Docker Engine 离线安装
**日期:** 2026-07-22

#### 任务1: 集成 Docker 离线安装包
- **目标:** 将 Docker Engine 安装包含到离线包中
- **行动:**
  - 添加 `docker-26.1.4.tgz` (Docker Engine 二进制文件, ~70MB)
  - 添加 `docker-compose` 二进制文件 (~60MB)
  - 修改 `deploy/install.sh`：
    - 检测 Docker 是否已安装
    - 如果未安装，从离线 tarball 安装
    - 安装 docker-compose 二进制
    - 创建 systemd 服务并启动 Docker daemon

---

### v1.4.0 - 镜像打包 (8个镜像)
**日期:** 2026-07-22

#### 任务1: 拉取并打包所有 Docker 镜像
- **目标:** 创建完整的离线镜像归档
- **行动:**
  - 运行 `deploy/offline-prep.sh` 拉取全部8个镜像：
    1. `python:3.11-slim`
    2. `nginx:1.27-alpine`
    3. `langgenius/dify-api:1.1.3`
    4. `langgenius/dify-web:1.1.3`
    5. `postgres:15.8-alpine`
    6. `redis:6.2.14-alpine`
    7. `semitechnologies/weaviate:1.19.0`
    8. `ollama/ollama:0.5.7` (从 0.1.60 更新)
  - 生成 `deploy-images.tar` (~2.4GB)
  - 重新生成 `fa-diagnosis-offline.tar.gz` (~2.5GB)

#### 任务2: 下载并导出 Ollama 模型
- **目标:** 准备离线使用的本地大模型
- **行动:**
  - 启动 Ollama 容器: `docker run -d -v ollama_models:/root/.ollama --name ollama ollama/ollama:0.5.7`
  - 拉取 Qwen2-7B 模型: `docker exec ollama ollama pull qwen2:7b`
  - 验证模型: `docker exec ollama ollama list` (4.4GB)
  - 导出模型数据卷: `docker run --rm -v ollama_models:/data -v "D:/idex:/backup" alpine tar -czhf /backup/ollama-models-qwen2-7b.tar.gz -C /data .`
  - 生成 `ollama-models-qwen2-7b.tar.gz` (~4GB)

---

### v1.5.0 - 公网版本
**日期:** 2026-07-22

#### 任务1: 创建公网部署版本包
- **目标:** 为有网络的服务器创建独立部署包
- **行动:**
  - 创建 `docker-compose-public.yml` (不含 Ollama 服务)
  - 创建 `deploy/install-public.sh` (简化的公网模式安装脚本)
  - 生成 `fa-diagnosis-public.tar.gz` (~2.4GB)
  - 核心区别: 使用 Dify 外部 LLM API 而非本地 Ollama

---

### v1.6.0 - API Key 配置
**日期:** 2026-07-22

#### 任务1: 配置 Dify API Key
- **目标:** 预配置 Dify 工作流 API Key
- **行动:**
  - 更新 `.env.example` 添加：
    - `DIFY_API_KEY=app-xrQqTDJn0P7RlW1FInXez83I` (FA 诊断工作流)
    - `DIFY_TRANSLATE_API_KEY=app-ODflsibcNRkEG0z7k1CWVvqA` (翻译工作流)

#### 任务2: 创建内网专用环境模板
- **目标:** 内网部署使用空 API Key
- **行动:**
  - 创建 `.env.offline.example`，`DIFY_API_KEY` 和 `DIFY_TRANSLATE_API_KEY` 为空
  - 更新 `deploy/install.sh` 使用 `.env.offline.example`
  - 更新 `deploy/install-public.sh` 使用 `.env.example`
  - 重新生成两个部署包

---

### v1.7.0 - 项目结构整理
**日期:** 2026-07-22

#### 任务1: 整理部署包结构
- **目标:** 创建公网和内网版本专用文件夹
- **行动:**
  - 创建 `public/` 文件夹：
    - `fa-diagnosis-public.tar.gz` (~2.4GB)
    - `docker-compose-public.yml`
  - 创建 `offline/` 文件夹：
    - `fa-diagnosis-offline.tar.gz` (~2.5GB)
    - `ollama-models-qwen2-7b.tar.gz` (~4GB)

#### 任务2: 清理临时文件
- **目标:** 删除不必要的文件和目录
- **行动:**
  - 删除 `__pycache__/` 目录
  - 删除 `api/__pycache__/`
  - 删除 `models/__pycache__/`
  - 删除 `services/__pycache__/`
  - 注意: `fa_data.db-shm` 和 `fa_data.db-wal` 无法删除（数据库正在使用中）

---

## 最终部署文件汇总

### 内网版本 (`offline/`)
| 文件 | 大小 | 描述 |
|------|------|------|
| `fa-diagnosis-offline.tar.gz` | ~2.5GB | 完整项目，包含 Docker 离线安装 |
| `ollama-models-qwen2-7b.tar.gz` | ~4GB | Qwen2-7B 大模型 |

### 公网版本 (`public/`)
| 文件 | 大小 | 描述 |
|------|------|------|
| `fa-diagnosis-public.tar.gz` | ~2.4GB | 完整项目（假设服务器已安装 Docker） |
| `docker-compose-public.yml` | ~4KB | 公网模式 Docker Compose 配置 |

### 核心组件
| 组件 | 状态 |
|------|------|
| Docker 镜像 (8个) | ✅ 已打包 |
| Docker Engine 离线安装 | ✅ 已包含（仅内网版本） |
| Docker Compose | ✅ 已包含 |
| Python 离线包 (23个) | ✅ 已打包 |
| 前端构建产物 | ✅ 已打包 |
| 后端代码 | ✅ 已打包 |
| 一键安装脚本 | ✅ 已创建 |
| Ollama 大模型支持 | ✅ 已集成（仅内网版本） |
| Dify 集成 | ✅ 已完成 |

---

## 部署说明

### 公网部署
```bash
mkdir -p /opt/fa && tar -xzf public/fa-diagnosis-public.tar.gz -C /opt/fa
cd /opt/fa && sudo bash deploy/install-public.sh --skip-confirm
```

### 内网部署
```bash
mkdir -p /opt/fa && tar -xzf offline/fa-diagnosis-offline.tar.gz -C /opt/fa
cd /opt/fa && sudo bash deploy/install.sh --skip-confirm
docker run --rm -v fa_ollama_models:/data -v /tmp:/backup alpine tar -xzhf /backup/ollama-models-qwen2-7b.tar.gz -C /data
docker compose restart ollama
```

### 内网部署后配置步骤
1. 登录 Dify: http://localhost:80 (admin/admin123456)
2. 配置 Ollama: 设置 → 模型供应商 → Ollama → http://ollama:11434
3. 创建诊断工作流并获取 API Key
4. 更新 `.env` 文件中的 `DIFY_API_KEY`
5. 重启后端: `docker compose restart backend`

---

## 已知问题 / 待处理事项
- [ ] `fa_data.db-shm` 和 `fa_data.db-wal` 文件需要在数据库停止后清理
- [ ] Ollama 模型下载需要网络连接（无法在容器内预下载）

---

## 作者
- 开发团队
- 最后更新: 2026-07-22