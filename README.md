# Docker Auto Build

基于 GitHub Actions 的自动化 Docker 镜像构建工具。从指定代码仓库拉取源码或 Release 产物，使用预定义的 Dockerfile 构建镜像，并推送到 DockerHub。

## 功能特点

- 支持多个代码仓库并行自动化构建
- 两种构建模式：源码编译 / 二进制 Release 下载
- 支持多平台构建（`linux/amd64`, `linux/arm64`）
- 自动标记 `latest` 版本和日期版本
- 支持 `build_args` 构建参数配置
- 推送触发 / PR 触发 / 手动触发

## 目录结构

```
.
├── config.yaml                     # 仓库构建配置
├── .github/workflows/docker-build.yml  # CI 工作流
└── dockerfiles/
    ├── <service-1>/                # 每个服务一个子目录
    │   ├── Dockerfile              # 必须：构建定义文件
    │   └── ...                     # 其他依赖文件（如 entrypoint.sh、config.json）
    └── <service-2>/
        └── Dockerfile
```

运行时会自动生成以下临时目录（已加入 `.gitignore`，无需手动创建）：
- `dockerfiles/<name>/repo/`  — 克隆的源码仓库（或 `git pull` 更新）
- `dockerfiles/<name>/release/` — 下载的 Release 产物

## 配置说明

在 `config.yaml` 中配置需要构建的仓库信息，每个仓库为一个列表项：

```yaml
repositories:
  - name: service-name          # 必填：服务名称，对应 dockerfiles/<name>/ 及镜像名
    repo_url: https://github.com/owner/repo.git  # 必填：代码仓库地址
    branch: main                 # 必填：要拉取的源码分支
    release_name: binary.tar.gz  # 可选：Release 产物文件名（模糊匹配）
    build_args:                  # 可选：构建参数（会作为 --build-arg 传入）
      ARG_KEY: value
```

### 字段说明

| 字段 | 必填 | 说明 |
|------|------|------|
| `name` | 是 | 服务名称，也是 DockerHub 镜像名（最终为 `$USERNAME/<name>`）和 `dockerfiles/` 下的子目录名 |
| `repo_url` | 是 | 源码仓库地址（仅支持 GitHub `.git` 地址） |
| `branch` | 是 | 要拉取的分支名 |
| `release_name` | 否 | 配置后将自动从最新 GitHub Release 下载匹配该名称的产物文件到 `release/` 目录，`.tar.gz` 文件会自动解压 |
| `build_args` | 否 | 构建参数键值对，注入到 Dockerfile 中的 `ARG` 指令 |

### 两种构建模式

**模式一：源码编译（默认）**

不配置 `release_name`，CI 会将仓库克隆到 `dockerfiles/<name>/repo/`，Dockerfile 中通过 `COPY ./repo/ .` 引用源码进行编译。

```yaml
- name: reality
  repo_url: https://github.com/XTLS/Xray-core.git
  branch: main
```

**模式二：二进制 Release 下载**

配置 `release_name` 后，CI 会从仓库最新 Release 中下载匹配的产物文件到 `dockerfiles/<name>/release/`，Dockerfile 中通过 `COPY ./release/<binary> ...` 直接使用。

```yaml
- name: realm
  repo_url: https://github.com/zhboner/realm.git
  branch: master
  release_name: realm-x86_64-unknown-linux-musl.tar.gz
```

## 使用方法

### 1. 准备 Secrets

在 GitHub 仓库 **Settings → Secrets and variables → Actions** 中添加：

| Secret | 说明 |
|--------|------|
| `DOCKERHUB_USERNAME` | DockerHub 用户名 |
| `DOCKERHUB_TOKEN` | DockerHub Access Token（需有读写权限） |

### 2. 添加服务

1. 在 `dockerfiles/` 下创建 `<service-name>/` 目录，编写 `Dockerfile`
2. 在 `config.yaml` 中添加对应的仓库配置
3. 提交并推送到 `main` 分支

### 3. 推送后的镜像命名规则

```
<DOCKERHUB_USERNAME>/<name>:latest
<DOCKERHUB_USERNAME>/<name>:<YYYYMMDD>
```

## 触发条件

| 触发方式 | 条件 |
|----------|------|
| Push 触发 | 向 `main`/`master` 推送且变更了 `dockerfiles/**` 或 `config.yaml` |
| PR 触发 | 向 `main`/`master` 发起 PR 且变更了 `dockerfiles/**` 或 `config.yaml` |
| 手动触发 | 在 GitHub Actions 页面点击 **Run workflow**（`workflow_dispatch`） |

## 注意事项

- DockerHub Token 必须有仓库的读写权限
- 源码仓库必须为 GitHub 公开仓库（或配置好访问凭证）
- `Dockerfile` 必须以 `dockerfiles/<name>/` 作为构建上下文
- `release_name` 使用模糊匹配：配置 `realm-linux.tar.gz` 可匹配 `realm-linux-v1.0.0.tar.gz`
- PR 触发的构建不会推送镜像，仅验证构建是否通过
