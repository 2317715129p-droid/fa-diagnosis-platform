# 部署 Bug 修复记录

> 来源：桌面 `部署Bug修复记录.docx`（公网版首次部署于阿里云 ECS 的踩坑记录）
> 环境：阿里云 ECS，Ubuntu 22.04.5 LTS，7.1 GB RAM，Docker 29.6.2；工具 FinalShell + SFTP；部署包 `fa-diagnosis-public.tar.gz`（~2.4 GB）

## Bug 1：Shell 脚本 `"$COMPOSE"` 引号包裹错误

- **日期**：2026-07-30
- **表现**：执行 `install-public.sh` 提示 `docker compose: command not found`，所有服务启动失败。
- **根因**：变量 `COMPOSE="docker compose"` 以 `"$COMPOSE"` 调用，Bash 把 `"docker compose"` 整体当一个命令名查找，而非拆成两个参数。
- **修复**：`deploy/install.sh`、`deploy/install-public.sh` 及 offline/public 副本中所有 `"$COMPOSE"` 改为 `$COMPOSE`，共修复 6 个文件、12 处引用。
- **影响**：deploy/install.sh、deploy/install-public.sh、public/deploy/、deploy_test/

## Bug 2：dify-api 容器 OpenDAL 存储配置缺失

- **日期**：2026-07-30
- **表现**：dify-api 反复崩溃重启（exit code 3），日志 `opendal.exceptions.ConfigInvalid: root is not specified`。
- **根因**：Dify 1.1.3 废弃旧 `STORAGE_TYPE: local`，强制 OpenDAL；compose 中 dify-api 缺 `STORAGE_TYPE=opendal`、`OPENDAL_SCHEME=fs`、`OPENDAL_FS_ROOT` 三项，导致初始化失败。
- **修复**：所有 compose（公网 3 份 + 内网 2 份）dify-api 段追加三项 OpenDAL 变量；服务器端 Python 脚本修补后重建 dify-api。
- **影响**：public/docker-compose-public.yml、docker-compose.yml、deploy_test/

## Bug 3：Dify 数据库迁移从未执行（Bug 2 连锁）

- **日期**：2026-07-30
- **表现**：dify-api 日志 `relation "api_tokens" does not exist`，前端无限 Loading。
- **根因**：Bug 2 导致 dify-api 自创建起一直崩溃，自动建表（flask db upgrade）从未触发，PostgreSQL 为空，77 张表全缺。
- **修复**：手动 `docker exec dify-api flask db upgrade`，建全 77 张表后重启。
- **影响**：dify-api 容器 + dify-postgres 库

## Bug 4：dify-web 容器 API 地址指向 localhost

- **日期**：2026-07-30
- **表现**：Bug 3 修复后 Dify 页面（:80/install）仍 Loading。
- **根因**：dify-web 的 `CONSOLE_API_URL/APP_API_URL/MARKETPLACE_API_URL` 默认 `http://127.0.0.1:5001`，指向容器自身 localhost。
- **修复**：compose 中 dify-web 段添加，三个 URL 改为 `http://dify-api:5001`（Docker 服务名），force-recreate。
- **影响**：docker-compose-public.yml 中 dify-web 段

## Bug 5：Dify 前端 JS 仍用编译时注入的 API 地址

- **日期**：2026-07-30
- **表现**：Bug 4 修复后仍卡 Loading，但 `/console/api/setup` 返回正常 JSON。
- **根因**：Next.js 的 `NEXT_PUBLIC_*` 在 `next build` 时编译进 JS bundle，运行时注入只对 SSR 生效，浏览器端 JS 仍用旧地址。
- **修复**：dify-web 追加 `NEXT_PUBLIC_CONSOLE_API_URL=`、`NEXT_PUBLIC_APP_API_URL=`、`NEXT_PUBLIC_MARKETPLACE_API_URL=` 设为空，回退同源经 dify-nginx 代理。
- **影响**：docker-compose-public.yml dify-web environment + 容器重建

## Bug 6：阿里云安全组未放行端口

- **日期**：2026-07-30
- **表现**：服务器内 localhost:3000/:80/:8000 正常，但公网 IP 访问超时。
- **根因**：阿里云 ECS 默认安全组屏蔽所有入方向，80/3000/8000 未放行。
- **修复**：ECS 控制台安全组入方向加 TCP 80/3000/8000，授权 0.0.0.0/0。
- **影响**：阿里云 ECS 安全组

## Bug 因果链总结

```
Bug 2 (OpenDAL 缺失)
  → Bug 3 (数据库未建表)
    → Bug 4 + Bug 5 (前端 API 地址错误)  形成连锁
      → Bug 6 (安全组端口未放行) 暴露公网不可达
```

1. OpenDAL 配置缺失 → dify-api 自创建起从未正常运行
2. dify-api 崩溃 → 自动建表脚本从未执行 → PostgreSQL 空库
3. 修复 Bug 2+3 后，Bug 4/5 暴露：dify-web JS bundle 中 API 地址编译时写死 localhost
4. 浏览器无法公网访问 → Bug 6：安全组端口未放行

**最终状态**：8 个服务全部 Up，FA 前端（:3000）/ 后端（:8000）/ Dify 控制台（:80）均可正常访问。

> 离线版（v2.0）在此基础上额外修复 24 项问题，详见 [离线部署手册](离线部署手册.md) 第八章。
