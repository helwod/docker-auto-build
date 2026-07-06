# Docker Auto Build

> 基于 GitHub Actions 的自动化 Docker 多镜像构建工具

克隆源码或下载 Release → 构建 `linux/amd64` + `linux/arm64` 镜像 → 推送 DockerHub / GHCR，并在下次运行时自动跳过无更新的项目。

---

## 工作流程

```
push / 手动触发
    │
    ▼
prepare job          ← 读取 config.yaml，生成 JSON 构建矩阵
    │
    ▼
build job × N（并行）
    │
    ├─ [1] 检查更新 ──── 比较源仓库最新 commit/tag 与上次记录，无变化则跳过
    ├─ [2] 克隆源码 ──── repo 模式 git clone --depth 1
    ├─ [3] 下载 Release ─ 匹配并下载最新 Release 产物
    ├─ [4] 路径预检 ──── 校验 Dockerfile 中 COPY/ADD 路径
    ├─ [5] 构建推送 ──── buildx 多平台构建 → 推送到 registry
    ├─ [6] 提交状态 ──── 将版本标记写入 .build-state/ 提交回仓库
    └─ [7] 更新描述 ──── 同步源仓库 README 到 DockerHub 描述页
```

---

## 快速开始

### 1. 准备 Token

| Registry | Token | 说明 |
|----------|-------|------|
| DockerHub | 自建 PAT | Account Settings → Personal Access Tokens → 勾选 **Read / Write / Delete** |
| GHCR | `GITHUB_TOKEN` | 自动提供，无需配置 |

### 2. 配置 Secrets

仓库 **Settings → Secrets and variables → Actions** → New repository secret：

| Secret | 值 |
|--------|-----|
| `DOCKERHUB_USERNAME` | DockerHub 用户名 |
| `DOCKERHUB_TOKEN` | 上一步创建的 PAT |

### 3. 编写 `config.yaml`

```yaml
repositories:
  - name: my-app
    repo_url: https://github.com/owner/repo.git
```

### 4. 推送触发

```bash
git add . && git commit -m "add my-app" && git push
```

镜像地址：`<username>/<name>:latest` + `:<YYYYMMDD>`

---

## 目录结构

```
.
├── config.yaml                        # 核心：所有仓库的构建配置
├── .github/workflows/docker-build.yml # CI 定义
├── .build-state/                      # 自动生成：各项目上次构建时的源码版本标记
│   ├── realm.txt
│   └── my-app.txt
├── README.md
└── dockerfiles/                       # 本地构建文件（按需）
    └── <name>/
        ├── Dockerfile                 # 本地 Dockerfile
        ├── config.toml                # 其他依赖
        └── entrypoint.sh
```

> `dockerfiles/<name>/repo/` 和 `dockerfiles/<name>/release/` 是 CI 临时目录（`.gitignore` 排除）。

---

## 配置参考

### 完整字段

```yaml
repositories:
  - name: service-name           # 必填
    build_type: repo             # 可选，默认 repo
    repo_url: https://github.com/owner/repo.git
    branch: main                 # 可选，不填自动检测
    release_name: binary.tar.gz  # 可选
    dockerfile: path/in/repo     # 可选，源仓库内 Dockerfile 路径
    context: /custom/path        # 可选，覆盖构建上下文
    registry: both               # 可选，默认 dockerhub
    build_args:                  # 可选
      VERSION: 1.0
```

### 字段一览

| 字段 | 默认 | 说明 |
|------|------|------|
| `name` | **必填** | 镜像名 = `<username>/<name>`，目录对应 `dockerfiles/<name>/`，含大写自动转小写 |
| `build_type` | `repo` | `dockerfile`：不克隆仓库，用本地 Dockerfile + Release 构建；`repo`：克隆源码编译 |
| `repo_url` | - | Git 仓库地址，支持 `.git` 结尾或省略 |
| `branch` | 仓库默认分支 | 不填时通过 GitHub API 自动获取 |
| `release_name` | - | 从最新 Release 模糊匹配下载，`.tar.gz` 自动解压 |
| `dockerfile` | `Dockerfile` | repo 模式下指定源仓库内 Dockerfile 的位置 |
| `context` | 自动推断 | 手动覆盖 Docker 构建上下文目录 |
| `registry` | `dockerhub` | 推送目标：`dockerhub` / `ghcr` / `both` |
| `build_args` | - | 键值对 → `docker build --build-arg KEY=VALUE` |

### `registry` 取值

| 值 | DockerHub | GHCR | 示例镜像名 |
|:--:|:--:|:--:|----|
| `dockerhub` | ✓ | ✗ | `<user>/<name>` |
| `ghcr` | ✗ | ✓ | `ghcr.io/<owner>/<name>` |
| `both` | ✓ | ✓ | 同时推送到两个 registry |

### 配置示例

```yaml
repositories:
  # dockerfile 模式 + Release 二进制 → 仅 GHCR
  - name: realm
    build_type: dockerfile
    repo_url: https://github.com/zhboner/realm.git
    release_name: realm-x86_64-unknown-linux-musl.tar.gz
    registry: ghcr

  # repo 模式 + 源仓库自带 Dockerfile → 双 registry
  - name: mermaid-live-editor
    build_type: repo
    repo_url: https://github.com/mermaid-js/mermaid-live-editor.git
    branch: develop
    registry: both

  # repo 模式 + 本地 Dockerfile → DockerHub
  - name: reality
    build_type: repo
    repo_url: https://github.com/XTLS/Xray-core.git
    registry: dockerhub
    # 在 dockerfiles/reality/Dockerfile 编写，COPY ./repo/... 引用源码
```

---

## 两种构建模式

### `dockerfile` 模式

```
不克隆源码 → 下载 Release → COPY ./release/xxx → 构建
```

- **Dockerfile 必须**在 `dockerfiles/<name>/Dockerfile`
- 构建上下文：`dockerfiles/<name>/`
- 适合只需要预编译二进制的项目

### `repo` 模式

```
git clone → 源码在 dockerfiles/<name>/repo/ → 编译 → 构建
```

- **Dockerfile 可选**，优先级：本地 → config.dockerfile → 源仓库根目录
- 本地 Dockerfile 上下文：`dockerfiles/<name>/`（用 `./repo/` 引用源码）
- 源仓库 Dockerfile 上下文：`dockerfiles/<name>/repo/`

---

## 路径约定

Dockerfile 中 `COPY` 源路径的根 = 构建上下文（Context）：

| 场景 | Context | COPY 写法 | 解析为 |
|------|---------|----------|--------|
| `dockerfile` 模式 | `dockerfiles/realm/` | `COPY ./release/realm /bin/` | `dockerfiles/realm/release/realm` |
| `repo` + 本地 Dockerfile | `dockerfiles/app/` | `COPY ./repo/src/ ./` | `dockerfiles/app/repo/src/` |
| `repo` + 源仓库 Dockerfile | `dockerfiles/app/repo/` | `COPY package.json ./` | `dockerfiles/app/repo/package.json` |

> 构建前会自动预检所有 COPY 路径，`MISS` 的会打印上下文目录结构。

---

## 增量构建

每次 Push 触发时，CI 先检查源仓库是否有更新：

| 模式 | 检测方式 | 基准值 |
|------|---------|--------|
| `repo` | 分支最新 commit SHA | `a1b2c3d...` |
| `dockerfile` + `release_name` | Release 最新 tag | `v2.9.4` |
| 本地 `dockerfiles/<name>/` | git diff HEAD~1 | 有文件变更即触发 |

- 标记存入 `.build-state/<name>.txt`，构建成功后提交回仓库
- Push 和手动触发均遵循增量判断；PR 始终强制构建
- 无更新时输出 `源码无更新，跳过构建`

---

## 镜像标签

每次构建生成两个标签，**一次构建同时打四个标签**（both 模式）：

```
DockerHub: <user>/<name>:latest   <user>/<name>:20260704
GHCR:      ghcr.io/<owner>/<name>:latest   ghcr.io/<owner>/<name>:20260704
```

---

## DockerHub 描述同步

构建成功后自动将源仓库 README 同步为 DockerHub `full_description`：

- 简短描述：`Auto-built from <repo_url>`
- 完整描述：仓库 URL + `---` + README 全文（上限 25000 字符）
- 仅当 `registry` 包含 dockerhub 时执行

---

## 触发条件

| 触发 | 条件 | push 镜像 | 更新描述 | 增量跳过 |
|------|------|:--:|:--:|:--:|
| **Push** | 推送到 main/master，变更 `dockerfiles/**`/`config.yaml`/workflow | ✓ | ✓ | ✓ |
| **手动** | Actions → Run workflow | ✓ | ✓ | ✓ |
| **PR** | PR 到 main/master | ✗ | ✗ | ✗（始终构建） |

---

## 所需权限

### workflow 级 permissions

```yaml
permissions:
  contents: write   # 提交 .build-state/ 状态文件
  packages: write   # 推送 GHCR
```

### DockerHub Token

`DOCKERHUB_TOKEN` 必须是 Personal Access Token，权限勾选 **Read / Write / Delete**。

---

## 常见问题

**Q: DockerHub 描述更新 401/403？**
A: Token 需要 Read + Write + Delete 三项全勾选。DockerHub → Personal Access Tokens → Edit Permissions。

**Q: 镜像名含大写报错？**
A: Docker 要求镜像名全小写。CI 会自动将 `91Writing` → `91writing`。

**Q: repo_url 没写 `.git` 报错？**
A: 支持 `.git` 结尾或省略，如 `https://github.com/owner/repo` 同样可用。

**Q: Release 下载报 "无法获取 Release 信息"？**
A: 未认证 GitHub API 限额 60 次/小时，矩阵并行任务的 API 调用可能超限。等待一小时重试。

**Q: repo 模式下 Dockerfile 路径报 MISS？**
A: 检查预检日志中的上下文目录结构。本地 Dockerfile 的 COPY 路径相对于 `dockerfiles/<name>/`，源仓库 Dockerfile 相对于 `repo/`。

**Q: 构建状态文件在哪里？**
A: `.build-state/` 目录，每个项目一个 txt 文件。构建成功后会由 CI 自动提交推送，无需手动维护。

**Q: GHCR 镜像是 private？**
A: 默认继承仓库可见性。GitHub → Packages → 对应的包 → Settings → Change visibility → Public。

**Q: `registry: both` 会构建两次吗？**
A: 不会。`docker buildx build` 一次构建，通过多个 `-t` 标签同时推送到两个 registry。
