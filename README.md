# Docker Auto Build

基于 GitHub Actions 的自动化 Docker 镜像构建工具。从指定 Git 仓库拉取源码或 Release 产物，构建多平台镜像并推送到 DockerHub。

## 功能特点

- **两种构建模式**：`dockerfile` 模式（本地 Dockerfile + Release 二进制）和 `repo` 模式（克隆源码编译）
- **多平台构建**：`linux/amd64`、`linux/arm64`
- **智能配置**：`branch` 不填则自动获取仓库默认分支；`repo` 模式下无本地 Dockerfile 则回退使用源仓库自带的
- **路径预检**：构建前自动校验 Dockerfile 中 COPY/ADD 路径是否存在，提前暴露问题
- **自动版本标记**：`latest` + 日期版本（`YYYYMMDD`）
- **三种触发方式**：Push / PR / 手动触发

## 目录结构

```
.
├── config.yaml                          # 仓库构建配置（核心）
├── .github/workflows/docker-build.yml   # CI 工作流
└── dockerfiles/                         # 本地 Dockerfile（按需）
    ├── <service-name>/
    │   ├── Dockerfile                   # 本地构建定义（可选，取决于 build_type）
    │   ├── config.toml                  # 其他依赖文件
    │   ├── release/                     # 运行时自动生成：下载的 Release 产物
    │   └── repo/                        # 运行时自动生成：克隆的源码仓库
    └── ...
```

## 快速开始

### 第一步：配置 Secrets

在 GitHub 仓库 **Settings → Secrets and variables → Actions** 中添加：

| Secret | 说明 |
|--------|------|
| `DOCKERHUB_USERNAME` | DockerHub 用户名 |
| `DOCKERHUB_TOKEN` | DockerHub Access Token（需读写权限） |

### 第二步：编辑 `config.yaml`

在 `repositories` 列表中添加要构建的项目，每个项目一个条目。最简配置只需 2 行：

```yaml
repositories:
  - name: my-app
    repo_url: https://github.com/owner/repo.git
```

### 第三步：编写 Dockerfile（按需）

- **`build_type: repo`**：如果源仓库自带 Dockerfile，无需创建本地文件；否则在 `dockerfiles/<name>/Dockerfile` 中编写
- **`build_type: dockerfile`**：必须在 `dockerfiles/<name>/Dockerfile` 中编写

### 第四步：推送触发构建

```bash
git add . && git commit -m "add my-app" && git push
```

推送后 GitHub Actions 自动开始构建。构建完成后的镜像：

```
<DOCKERHUB_USERNAME>/<name>:latest
<DOCKERHUB_USERNAME>/<name>:20260703
```

## 配置详解

### `config.yaml` 完整字段

```yaml
repositories:
  - name: my-service              # 必填：服务名称 / 镜像名 / dockerfiles 子目录名
    build_type: dockerfile        # 可选：构建模式，默认 repo
    repo_url: https://github.com/owner/repo.git  # repo 模式或需要下载 Release 时必填
    branch: main                  # 可选：git 分支，不填自动获取仓库默认分支
    release_name: binary.tar.gz   # 可选：Release 文件名（模糊匹配），自动下载并解压
    dockerfile: path/to/Dockerfile  # 可选：源仓库内 Dockerfile 子路径（仅 repo 模式）
    build_args:                   # 可选：构建参数，注入 Dockerfile ARG 指令
      VERSION: 1.0.0
```

### 字段说明

| 字段 | 必填 | 默认值 | 说明 |
|------|:--:|--------|------|
| `name` | 是 | - | 镜像名，对应 `dockerfiles/<name>/` 目录 |
| `build_type` | 否 | `repo` | `dockerfile`：仅本地文件编译；`repo`：克隆仓库编译 |
| `repo_url` | 视情况 | - | `dockerfile` 模式可省略；下载 Release 或 `repo` 模式必填 |
| `branch` | 否 | 仓库默认分支 | Git 分支，不填从 GitHub API 自动获取 |
| `release_name` | 否 | - | 匹配最新 Release 中的产物文件名，`.tar.gz` 自动解压 |
| `dockerfile` | 否 | `Dockerfile` | `repo` 模式下，指定源仓库内 Dockerfile 的相对路径 |
| `build_args` | 否 | - | 键值对，传递到 `docker build --build-arg` |

### 配置文件示例

```yaml
repositories:
  # 示例一：dockerfile 模式 — 用本地 Dockerfile + Release 二进制
  - name: realm
    build_type: dockerfile
    repo_url: https://github.com/zhboner/realm.git
    release_name: realm-x86_64-unknown-linux-musl.tar.gz

  # 示例二：repo 模式 — 克隆仓库后用源仓库自带 Dockerfile 编译
  - name: mermaid-live-editor
    build_type: repo
    repo_url: https://github.com/mermaid-js/mermaid-live-editor.git
    branch: develop

  # 示例三：repo 模式 + 本地 Dockerfile 覆盖 — 自定义构建逻辑
  - name: my-app
    build_type: repo
    repo_url: https://github.com/owner/repo.git
    # 在 dockerfiles/my-app/Dockerfile 中编写，上下文为 dockerfiles/my-app/
```

## 两种构建模式对比

| | `dockerfile` 模式 | `repo` 模式 |
|--|:--:|:--:|
| 克隆源码 | ✗ | ✓ |
| 本地 Dockerfile | **必须** | 可选（回退使用源仓库自带） |
| 构建上下文 | `dockerfiles/<name>/` | 有本地 Dockerfile → `dockerfiles/<name>/` |
| | | 无本地 → `dockerfiles/<name>/repo/` |
| Dockerfile COPY 路径约定 | 相对于 `dockerfiles/<name>/` | 本地：相对于 `dockerfiles/<name>/`（如 `./repo/...`） |
| | | 源仓库：相对于 `repo/` 根目录 |
| 适用场景 | 预编译二进制镜像 | 源码编译、多阶段构建 |

### 路径约定详解

**`dockerfile` 模式**：构建上下文始终为 `dockerfiles/<name>/`，Dockerfile 中的路径都相对于此目录。

```dockerfile
# dockerfiles/realm/Dockerfile  — 上下文：dockerfiles/realm/
COPY ./release/realm /usr/local/bin/realm     # → dockerfiles/realm/release/realm
COPY ./config.toml /etc/realm/config.toml      # → dockerfiles/realm/config.toml
```

**`repo` 模式 + 本地 Dockerfile**：上下文为 `dockerfiles/<name>/`，通过 `./repo/` 引用克隆的源码。

```dockerfile
# dockerfiles/my-app/Dockerfile  — 上下文：dockerfiles/my-app/
COPY ./repo/package.json ./            # → dockerfiles/my-app/repo/package.json
COPY ./repo/src/ ./src/                # → dockerfiles/my-app/repo/src/
```

**`repo` 模式 + 源仓库 Dockerfile**：上下文为 `dockerfiles/<name>/repo/`，路径即仓库内的相对路径。

```dockerfile
# mermaid-live-editor 仓库自带的 Dockerfile — 上下文：dockerfiles/mermaid-live-editor/repo/
COPY package.json ./
RUN npm install
COPY . ./
```

## Dockerfile 路径预检

每次构建前，CI 会自动提取 Dockerfile 中所有 `COPY`/`ADD` 源路径，在构建上下文目录中逐一验证是否存在：

```
[预检] 验证 COPY/ADD 路径...
  OK  ./release/realm
  MISS  ./repo/public/default.conf  (上下文: dockerfiles/mermaid-live-editor)

========================================
[预检] 上下文目录结构 (dockerfiles/mermaid-live-editor):
dockerfiles/mermaid-live-editor/
dockerfiles/mermaid-live-editor/repo/
dockerfiles/mermaid-live-editor/repo/Dockerfile
...
========================================
提示: COPY 源路径是相对于构建上下文 (dockerfiles/mermaid-live-editor) 的
```

`MISS` 表示路径在上下文中不存在，可根据打印的目录结构快速定位问题。

## 触发条件

| 触发方式 | 条件 | 是否推送镜像 |
|----------|------|:--:|
| Push 触发 | 推送至 `main`/`master`，变更了 `dockerfiles/**`、`config.yaml` 或 workflow | ✓ |
| PR 触发 | PR 至 `main`/`master`，变更了上述文件 | ✗（仅验证构建） |
| 手动触发 | Actions 页面 → **Run workflow** | ✓（主分支时） |

## 镜像标签

每次成功构建后生成两个标签：

```
<DOCKERHUB_USERNAME>/<name>:latest       # 始终指向最新构建
<DOCKERHUB_USERNAME>/<name>:20260703     # 日期标签，方便回滚
```

## 常见问题

**Q: `release_name` 无法匹配？**
A: `release_name` 使用模糊匹配（`contains`），只需包含能唯一标识文件的字样，如 `linux-amd64` 可匹配 `app-linux-amd64-v2.0.tar.gz`。

**Q: repo 模式下构建报 "not found"？**
A: 查看预检日志确认路径是否正确。本地 Dockerfile 中路径相对于 `dockerfiles/<name>/`，源仓库 Dockerfile 中路径相对于 `repo/`。

**Q: 如何只在原来基础上更新源码？**
A: workflow 每次运行都会重新 `git clone --depth 1`，无需本地干预。

**Q: 默认分支是什么？**
A: 不填 `branch` 时，CI 会调用 GitHub API 获取仓库真实的默认分支（`main`、`master` 或 `develop`）。

**Q: 不想要自动生成的 `repo/` 和 `release/` 目录？**
A: 它们已在 `.gitignore` 中排除，仅在 CI 运行时临时生成，不会污染仓库。
