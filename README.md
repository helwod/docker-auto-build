# Docker Auto Build

基于 GitHub Actions 的自动化 Docker 镜像构建工具。从 Git 仓库拉取源码或 Release 产物，构建多平台镜像并同时推送到 DockerHub 和 GHCR，自动同步仓库 README 作为镜像描述。

---

## 工作流概览

```
config.yaml  →  prepare Job  →  build Job (矩阵并行)  →  DockerHub + GHCR
               读取配置生成        ├─ 克隆源码 (repo 模式)
               构建矩阵          ├─ 下载 Release
                                 ├─ 路径预检
                                 ├─ docker buildx build (多平台)
                                 └─ 更新 DockerHub 描述
```

每次推送会自动执行五个阶段：

| 阶段 | 条件 | 说明 |
|------|------|------|
| 克隆源码 | `build_type=repo` | `git clone --depth 1` 到 `dockerfiles/<name>/repo/` |
| 下载 Release | 配置了 `release_name` | 从 GitHub Release 下载并解压到 `release/` |
| 路径预检 | 始终 | 校验 Dockerfile 中 COPY/ADD 源路径是否存在 |
| 构建推送 | 始终 | `linux/amd64` + `linux/arm64`，PR 仅构建不推送 |
| 更新描述 | 非 PR 且 registry 含 dockerhub | 同步仓库 README 到 DockerHub 描述 |

---

## 快速开始

### 第一步：创建 DockerHub Token

访问 [DockerHub → Account Settings → Personal Access Tokens](https://hub.docker.com/settings/security)，创建 Token，权限选择 **Read, Write, Delete**。

> GHCR 不需要额外 Token，直接使用 GitHub Actions 自带的 `GITHUB_TOKEN`。

### 第二步：配置 GitHub Secrets

仓库 **Settings → Secrets and variables → Actions** 添加：

| Secret | 值 | 用途 |
|--------|-----|------|
| `DOCKERHUB_USERNAME` | DockerHub 用户名 | DockerHub 登录 + 镜像名 |
| `DOCKERHUB_TOKEN` | 上一步创建的 Access Token | DockerHub 登录 + 描述更新 |

### 第三步：编辑 `config.yaml`

```yaml
repositories:
  - name: my-app               # 镜像名 = <username>/my-app
    repo_url: https://github.com/owner/repo.git
    registry: both             # 同时推送 DockerHub + GHCR
```

### 第四步：编写 Dockerfile（按需）

在 `dockerfiles/<name>/` 下编写 Dockerfile（仅 `dockerfile` 模式或需要自定义构建时）。

### 第五步：推送触发构建

```bash
git add . && git commit -m "add my-app" && git push
```

---

## 目录结构

```
.
├── config.yaml                          # 核心：仓库构建配置
├── .github/workflows/docker-build.yml   # CI 工作流定义
├── README.md
└── dockerfiles/                         # 本地构建文件（按需）
    └── <service-name>/
        ├── Dockerfile                   # 本地 Dockerfile
        ├── config.toml                  # 其他依赖文件
        └── entrypoint.sh                # 入口脚本
```

> `dockerfiles/<name>/repo/` 和 `dockerfiles/<name>/release/` 是 CI 运行时临时目录，已在 `.gitignore` 中排除。

---

## 配置详解

### 完整配置字段

```yaml
repositories:
  - name: service-name              # 必填
    build_type: repo                # 可选，默认 repo
    repo_url: https://github.com/owner/repo.git
    branch: main                    # 可选，不填自动检测仓库默认分支
    release_name: binary.tar.gz     # 可选
    dockerfile: path/to/Dockerfile  # 可选，源仓库内 Dockerfile 子路径
    context: dockerfiles/name/repo  # 可选，手动覆盖构建上下文
    registry: both                  # 可选，默认 dockerhub
    build_args:                     # 可选
      VERSION: 1.0.0
```

### 字段说明

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|------|------|:--:|--------|------|
| `name` | string | 是 | - | 镜像名 = `<username>/<name>`，对应 `dockerfiles/<name>/` 目录 |
| `build_type` | string | 否 | `repo` | `dockerfile`：不克隆仓库，仅用本地文件 + Release 构建；`repo`：克隆仓库后编译 |
| `repo_url` | string | 视情况 | - | `dockerfile` 模式可省略；配置了 `release_name` 或 `build_type=repo` 时必填 |
| `branch` | string | 否 | 仓库默认分支 | 不填时通过 GitHub API 自动获取仓库默认分支（`main`/`master`/`develop`） |
| `release_name` | string | 否 | - | 从最新 Release 中按名称 `contains` 模糊匹配下载产物，`.tar.gz`/`.tgz` 自动解压 |
| `dockerfile` | string | 否 | `Dockerfile` | 仅 `repo` 模式生效，指定源仓库内 Dockerfile 的相对路径 |
| `context` | string | 否 | 自动推断 | 手动覆盖 Docker 构建上下文目录 |
| `registry` | string | 否 | `dockerhub` | 推送目标：`dockerhub` / `ghcr` / `both`（同时推送） |
| `build_args` | object | 否 | - | 键值对，传入 `docker build --build-arg KEY=VALUE` |

### `registry` 推送目标详解

| 值 | DockerHub | GHCR | 镜像名 |
|:--:|:--:|:--:|------|
| `dockerhub` | ✓ | ✗ | `<DOCKERHUB_USERNAME>/<name>` |
| `ghcr` | ✗ | ✓ | `ghcr.io/<github_owner>/<name>` |
| `both` | ✓ | ✓ | 两个 registry 各一份 |

**GHCR 认证**：使用 GitHub Actions 自带的 `GITHUB_TOKEN`，无需额外配置 Secret。工作流已声明 `packages: write` 权限。

**DockerHub 认证**：使用 `DOCKERHUB_USERNAME` + `DOCKERHUB_TOKEN` Secrets，Token 需 **Read, Write, Delete** 权限。

### 配置示例

```yaml
repositories:
  # 例 1：同时推送 DockerHub + GHCR，dockerfile 模式 + Release 二进制
  - name: realm
    build_type: dockerfile
    repo_url: https://github.com/zhboner/realm.git
    release_name: realm-x86_64-unknown-linux-musl.tar.gz
    registry: both

  # 例 2：仅推送 GHCR，repo 模式，源仓库自带 Dockerfile
  - name: mermaid-live-editor
    build_type: repo
    repo_url: https://github.com/mermaid-js/mermaid-live-editor.git
    branch: develop
    registry: ghcr

  # 例 3：仅推送 DockerHub，repo 模式 + 本地 Dockerfile
  - name: reality
    build_type: repo
    repo_url: https://github.com/XTLS/Xray-core.git
    branch: main
    registry: dockerhub
    # 在 dockerfiles/reality/Dockerfile 中编写，COPY 路径用 ./repo/ 引用源码
```

---

## 两种构建模式深入

### `dockerfile` 模式工作流

```
config.yaml      不克隆仓库
release_name  →  下载 Release → 解压到 dockerfiles/<name>/release/
                  ↓
                 使用 dockerfiles/<name>/Dockerfile
                 构建上下文 = dockerfiles/<name>/
                  ↓
                 推送镜像到 DockerHub / GHCR
```

- **Dockerfile 必须**存在于 `dockerfiles/<name>/Dockerfile`
- **构建上下文**：`dockerfiles/<name>/`
- **不克隆源码**仓库，只下载 Release 产物的二进制文件
- Dockerfile 中 `COPY ./release/xxx` → 引用下载的 Release 文件

### `repo` 模式工作流

```
config.yaml
repo_url → git clone --depth 1 → dockerfiles/<name>/repo/
           ↓
           Dockerfile 解析（优先级从高到低）：
           ① 本地 dockerfiles/<name>/Dockerfile → 上下文: dockerfiles/<name>/
           ② config.dockerfile 指定路径     → 上下文: dockerfiles/<name>/repo/
           ③ 源仓库根目录 Dockerfile        → 上下文: dockerfiles/<name>/repo/
           ↓
           构建 + 推送
```

- **Dockerfile 可选**：源仓库自带则直接用；否则在本地 `dockerfiles/<name>/Dockerfile` 编写
- **构建上下文**：本地 Dockerfile → `dockerfiles/<name>/`（用 `./repo/` 引用源码）；源仓库 Dockerfile → `dockerfiles/<name>/repo/`
- 克隆使用 `--depth 1` 浅克隆，节省时间和空间

---

## 路径约定

Dockerfile 中 `COPY`/`ADD` 的源路径是**相对于构建上下文的**。不同场景下上下文不同：

| 场景 | 构建上下文 | COPY 写法示例 | 实际路径 |
|------|-----------|-------------|---------|
| dockerfile 模式 | `dockerfiles/realm/` | `COPY ./release/realm /bin/` | `dockerfiles/realm/release/realm` |
| repo + 本地 Dockerfile | `dockerfiles/reality/` | `COPY ./repo/main/ ./` | `dockerfiles/reality/repo/main/` |
| repo + 源仓库 Dockerfile | `dockerfiles/mermaid/repo/` | `COPY package.json ./` | `dockerfiles/mermaid/repo/package.json` |

> **路径预检**会在构建前自动校验所有 COPY 路径，`MISS` 标记的路径会打印上下文目录结构帮助排查。

---

## 镜像标签

每次成功构建生成两个标签：

| 标签 | 说明 |
|------|------|
| `:latest` | 始终指向最新构建 |
| `:YYYYMMDD` | 日期版本，方便回滚和追溯 |

**镜像地址**：

```
# DockerHub
<DOCKERHUB_USERNAME>/<name>:latest
<DOCKERHUB_USERNAME>/<name>:20260704

# GHCR
ghcr.io/<github_owner>/<name>:latest
ghcr.io/<github_owner>/<name>:20260704
```

---

## DockerHub 描述同步

镜像推送成功后，工作流会自动将**源仓库的 README** 同步为 DockerHub 镜像描述（仅当 `registry` 含 dockerhub 时）：

- **简短描述**：`Auto-built from <repo_url>`
- **完整描述**：`## Source Repository\n<url>\n---\n<README 内容>`
- **README 来源**：repo 模式从克隆仓库读取；dockerfile 模式通过 GitHub API 获取
- **限制**：DockerHub `full_description` 最大 25000 字符，超出自动截断
- **认证**：Token 需具有 **Read, Write, Delete** 权限
- **GHCR**：无对应 API，不更新描述

---

## 触发条件

| 触发方式 | 条件 | 推送镜像 | 更新描述 |
|----------|------|:--:|:--:|
| Push | 推送至 `main`/`master`，变更 `dockerfiles/**`、`config.yaml` 或 workflow | ✓ | ✓ |
| Pull Request | PR 至 `main`/`master`，变更上述文件 | ✗ | ✗ |
| 手动触发 | Actions 页面 → Run workflow | ✓ | ✓ |

> PR 触发仅验证构建是否通过，不会推送镜像或更新描述。

---

## 构建参数

通过 `build_args` 字段向 Dockerfile 注入参数：

```yaml
- name: my-app
  repo_url: https://github.com/owner/repo.git
  build_args:
    VERSION: 1.2.3
    GOLANG_VERSION: 1.21
```

Dockerfile 中通过 `ARG` 指令接收：

```dockerfile
ARG VERSION
ARG GOLANG_VERSION
FROM golang:${GOLANG_VERSION}-alpine AS builder
RUN echo "Building version: ${VERSION}"
```

---

## 所需权限

### GitHub Actions 权限

工作流已声明：

```yaml
permissions:
  contents: read      # 读取仓库代码
  packages: write     # 推送到 GHCR
```

### DockerHub Token 权限

| 权限 | 用途 |
|------|------|
| Read | 拉取基础镜像、读取仓库信息 |
| Write | 推送镜像、更新描述 |
| Delete | 清理旧标签（预留） |

---

## 常见问题

**Q: 权限报错 401/403？**
A: DockerHub Access Token 需要 **Read, Write, Delete** 权限。
DockerHub → Account Settings → Personal Access Tokens → 选择 Token → Edit Permissions → 确保三项全勾选。

**Q: 描述更新失败但不影响构建？**
A: 描述更新是独立步骤，失败不会阻断构建。检查日志中 `Update DockerHub description` 步骤的 HTTP 状态码。

**Q: GHCR 镜像是 private？**
A: GHCR 默认继承仓库可见性。到 GitHub → Packages → 对应包 → Settings → Change visibility → Public。

**Q: Dockerfile 中路径报 "not found"？**
A: 查看构建日志中 `[预检]` 部分。COPY 源路径是相对于构建上下文（Context）的，打印的目录结构可帮助定位。

**Q: repo 模式和 dockerfile 模式怎么选？**
A: 源码需要编译（go build / npm build）→ `repo` 模式；只需下载预编译二进制 → `dockerfile` 模式。

**Q: 为什么 Dockerfile 中是 `COPY ./repo/...` 而不是直接 `COPY . .`？**
A: `repo` 模式 + 本地 Dockerfile 时，构建上下文是 `dockerfiles/<name>/`，源码在 `./repo/` 子目录下。

**Q: branch 不填会怎样？**
A: 工作流调用 `GitHub API GET /repos/{owner}/{repo}` 获取 `default_branch` 字段，自动适配 `main`/`master`/`develop` 等。

**Q: release_name 匹配规则？**
A: 使用 `jq contains` 模糊匹配。如配置 `linux-amd64` 可匹配 `app-linux-amd64-v2.0.tar.gz`。

**Q: Release 下载报 "无法获取 Release 信息"？**
A: 通常是 GitHub API 限流（未认证 60 次/小时）。矩阵任务并行调用 API，短时间可能超限。等待一小时后重试。

**Q: registry: both 会构建两次吗？**
A: 不会。只构建一次，通过多个 `-t` 标签同时推送到两个 registry，构建时间不变。
