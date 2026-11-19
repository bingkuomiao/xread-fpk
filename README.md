# XRead FPK（飞牛 fnOS 原生版）

> 自托管阅读应用 **XRead** 的飞牛 fnOS 原生安装包（`.fpk`）打包工程。
> 当前应用版本 **1.0.48.69**，离线安装、无需 Docker。
>
> 本工程是 [bingkuomiao/xread-fpk](https://github.com/bingkuomiao/xread-fpk) 的打包工程主体；
> 老的源码仓库已归档为 [xread-fpk2](https://github.com/bingkuomiao/xread-fpk2)。

---

## 1. 应用简介

**XRead（阅读）** 是一款自托管的阅读/书源应用，后端用 Rust（axum）编写，现代前端用 Vue 3。
本仓库负责把它打包成飞牛 fnOS 可直接安装的 `.fpk` 原生应用：

- **离线安装**：二进制与前端资源全部内置，不依赖 Docker，不访问公网 registry。
- **书源生态**：兼容 Legado（阅读 3.0）书源，支持发现、搜索、书源管理。
- **阅读能力**：TXT / EPUB 导入、批量缓存、多用户隔离、AI 助读、音视频流代理。
- **三端覆盖**：同一服务、同一端口，手机 / PC 现代浏览器与 Kindle 老浏览器均可使用（见下）。
- **向导可配**：安装向导可设置鉴权、公开只读、缓存并发、书源测试超时等运行参数。

### 三端支持

| 设备 / 浏览器 | 使用前端 | 访问地址 | API 方式 |
|---|---|---|---|
| 手机 / PC（现代浏览器） | XRead Vue 3 前端 | `http://<NAS>:7777/` | 调后端 `/reader3/*` |
| Kindle（老 WebKit 浏览器） | XRead-kindle 静态前端 | `http://<NAS>:7777/xread/` | 同源 `/reader3/*`，**免 CORS** |

> Kindle 老浏览器访问 `/xread/`（末尾斜杠建议保留），页面自动以同源方式回源后端 API，
> 无需手填 IP:端口。详见 [Kindle 支持专文](docs/kindle/README.md)。

---

## 2. 版本信息

| 项 | 值 | 说明 |
|---|---|---|
| **FPK 应用版本 / `manifest.version`** | **1.0.48.93** | 安装包版本，同时是产物文件名 |
| 前端版本（设置页显示） | 1.0.48.93 | 来自 `xread/frontend/package.json` |
| 后端 `appVersion` | 1.0.48 | 固定，后端二进制不随前端改动 |
| Kindle 前端 `frontVersion` | 1.0.48.93 | 写入 `appVersion` / `frontVersion` 运行配置 |

打包时 `XREAD_VERSION` 应与前端版本一致（默认已是 `1.0.48.93`）。

---

## 3. 定位：本工程只负责打包

本工程**不再是前后端源码基线**。源码基线改为两个独立仓库，打包时从它们拉取最新产物统一组装：

| 源码基线 | 提供什么 | 本地默认路径 |
|---|---|---|
| [`bingkuomiao/xread`](https://github.com/bingkuomiao/xread) | Rust 后端（二进制）+ Vue 3 前端（源码，需编译） | `../xread` |
| [`bingkuomiao/xread-kindle`](https://github.com/bingkuomiao/xread-kindle) | Kindle / 手机 / PC 静态前端（源码即产物，直接复制） | `../kabi-reader` |

流程：**从这两个仓库取最新产物 → 组装 → fnpack 打包成 `.fpk`**。
后端二进制默认用工程内已验证基线，也可用 `--fetch-backend` 从 xread 的 `backend-latest` Release 拉最新产物。

---

## 4. 目录结构

```
xread-fpk/
├── build.sh                  # 主构建脚本（取产物→编译前端→注入配置→组装→打包→校验）
├── manifest                  # fpk 元数据模板（version/port 由脚本注入）
├── ICON.PNG / ICON_256.PNG    # 应用图标
├── backend/                  # 后端二进制：amd64/arm64 静态 ELF（默认基线 / fetch 更新）
│   ├── xread-amd64
│   ├── xread-arm64
│   └── SHA256SUMS            # fetch-backend 生成
├── cmd/ config/ wizard/      # fnOS 打包壳（安装/配置回调、权限、安装向导）
├── tools/
│   ├── fnpack                # fnOS 打包器 1.2.3
│   ├── patch_dist.py         # 产物层注入运行时配置（不改前端源码）
│   └── fetch-backend.sh      # 从 xread 的 backend-latest Release 拉最新后端二进制
├── .github/
│   ├── workflows/build-fpk.yml  # 构建 FPK 的工作流（当前仅手动触发，自动触发已注释）
│   └── build-state.json         # 上次成功构建的源码状态（CI 自动回写，避免空转）
├── tests/
│   └── run-tests.sh             # 轻量回归测试（语法/配置/版本/幂等/拉取安全，离线可跑）
├── frontend-dist/            # 【生成，不入库】Vue3 前端编译产物（可缓存复用）
├── dist/                     # 【生成，不入库】最终 .fpk 产物
├── README.md                 # 本文档：应用说明 + 打包工程手册
├── docs/                     # 说明文档归档（见下方文档索引）
│   ├── README.md             # 文档中心索引
│   ├── kindle/               # Kindle 前端专文
│   ├── wsl2/                 # Win10 + WSL2 本地运行文档
│   └── 验证报告.md           # 本地端到端验证记录
```

---

## 5. 快速开始

前置：本地已有 `xread` 与 `xread-kindle` 克隆（默认相对路径 `../xread`、`../kabi-reader`），装有 Node.js / npm / python3。

```bash
# 标准打包（默认版本 1.0.48.69、端口 7777）
./build.sh

# 打包前先更新两个源码仓库（git pull --ff-only）
./build.sh --pull

# 打包前从 xread@backend-latest 拉最新后端二进制（SHA256 校验）
./build.sh --fetch-backend

# 三件套全拉：前端源码 + 后端二进制都取最新
./build.sh --pull --fetch-backend

# 指定版本与端口
XREAD_VERSION=1.0.48.69 XREAD_PORT=7777 ./build.sh

# 自定义仓库路径 / 输出目录
XREAD_SRC=/path/to/xread KINDLE_SRC=/path/to/xread-kindle XREAD_OUT=/tmp/out ./build.sh

# 调试：跳过前端编译，复用上次 frontend-dist/
SKIP_FE=1 ./build.sh

# 调试：只打 FPK，跳过 WSL2 包
SKIP_WSL2=1 ./build.sh
```

**产物（每次构建默认同时产出两个同源包，二进制/前端完全一致）：**

| 产物 | 用途 |
| --- | --- |
| `dist/xread-native-<版本>.fpk` | 飞牛 fnOS 原生安装包 |
| `dist/xread-wsl2-<版本>.tar.gz` | Win10 + WSL2 开箱即用部署包 |

> **双包约定（长期）**：后续每次新版本更新，都必须同时给出 `.fpk` 与 wsl2 `.tar.gz` 两个包。
> WSL2 包由 `scripts/build-wsl2-package.sh` 生成，主 `build.sh` 在 FPK 完成后自动调用，
> 复用同一批 `backend/` 二进制与 `frontend-dist/` 前端，保证两包同源。
> WSL2 部署/测试文档见 [docs/wsl2/](docs/wsl2/README.md)（deploy / testing / build-package /
> xread-wsl2-lan.ps1）。使用：解压后 `./start.sh -d` 启动，Windows 管理员 PowerShell 跑
> `xread-wsl2-lan.ps1` 配转发，Kindle 访问 `http://192.168.137.1:7777/xread`。

---

## 6. 构建流程详解

1. **前置检查**：校验两个源码仓库、后端二进制、fnpack、Node 环境；`--pull` 时先更新仓库；`--fetch-backend` 时先从 Release 拉最新后端二进制。
2. **编译 Vue3 前端**：在 `xread/frontend` 执行 `npm run build`；校验其 `package.json` 版本与请求打包版本一致，产物缓存到 `frontend-dist/`。
3. **运行时配置注入**：`tools/patch_dist.py` 在产物层给 `index.html` 注入
   `window.__XREAD_CONFIG__={cacheConcurrency:4,testSourceTimeout:120}`，**不改任何前端源码**。
4. **组装**：
   - 壳文件：`manifest` / ICON / `cmd/` / `config/` / `wizard/`
   - 后端：`backend/xread-{amd64,arm64}` → `app/bin/`
   - Vue3 前端：`frontend-dist/` → `app/web/dist/`
   - Kindle 前端：`xread-kindle/` → `app/kindle/`，并挂到 `app/web/dist/xread/` 子路径
5. **参数注入**：版本写入 `manifest`，端口写入 `manifest` / `app/ui/config` / `cmd/main`。
6. **校验**：文件齐全、JSON 合法、运行时配置、版本号、双架构静态 ELF、图标尺寸。
7. **打包**：`fnpack build` → `dist/xread-native-<版本>.fpk`。

---

## 7. Kindle 支持

本包内置一份兼容后端 `/reader3/*` API 的**静态阅读前端 XRead-kindle**，专为 Kindle 等老 WebKit 浏览器准备，
与 Vue 3 前端**共存于同一服务、同一端口**：

- 挂载位置：构建时由 `app/kindle/` 拷贝为 `app/web/dist/xread/`，部署到运行时 `WEB_ROOT/xread/`。
- 访问方式：`http://<NAS>:7777/xread/`，页面全部使用相对路径，由后端静态兜底路由自动补 `index.html`。
- 同源 API：前端 `address` 留空，运行时由 `pageOrigin()` 拼出加载页的来源（**不用 `location.origin`**，老 Kindle 无此属性），免 CORS、无需手填 IP:端口。
- 兼容性：ES5 JavaScript、CRLF 换行、块级 / 固定 px 布局，兼容 Kindle WebKit 534；字体框、关于本机弹窗、书籍管理等按老内核特性专门适配。

访问方式、部署原理、目录结构与更新方法详见 **[Kindle 支持专文](docs/kindle/README.md)**。

---

## 8. 飞牛安装向导的运行参数

向导可配置：缓存并发（默认 4）、书源测试超时（默认 **120s**，范围 1-120）等。
`cmd/main` 启动时按向导值替换 `index.html` 里的 `window.__XREAD_CONFIG__` 占位。

- 飞牛打包环境：向导注入值优先（范围 1-120）。
- 独立部署（无注入）：前端 `source.ts` 的 `testSourceTimeoutMs()` 回退默认 **120s**，保证可用。

两处默认值已对齐为 120s。

---

## 9. 后端二进制说明

后端二进制有两种来源：

1. **固定基线（默认）**：`backend/` 中随工程维护的双架构静态 ELF（从已验证的 `xread-native-1.0.48.69.fpk` 提取，appVersion 1.0.48）。离线可用。
2. **最新产物**：xread 的 `build-backend.yml` 工作流在后端代码变更时自动交叉编译双架构 musl 静态二进制，并发布到滚动 Release `backend-latest`（含 `xread-amd64` / `xread-arm64` / `SHA256SUMS`）。用 `./tools/fetch-backend.sh` 或 `./build.sh --fetch-backend` 拉取，脚本**校验 SHA256 + 静态 ELF**后才替换本地基线，失败不动基线。

> `xread` 主仓库不提供预编译二进制，故后端走"基线 + Release 拉取"两条路；前端走源码编译 / `git pull`。

### 后端自动编译工作流（在 xread 仓库）

`xread/.github/workflows/build-backend.yml`：

- **触发**：`src/**`、`tests/**`、`Cargo.toml`、`Cargo.lock`、`.cargo/**`、`build.rs`、工作流自身变更，或手动 `workflow_dispatch`
- **编译**：矩阵双架构 `x86_64-unknown-linux-musl` / `aarch64-unknown-linux-musl`，用 `cross`
- **校验**：`file` 检查 64 位 ELF + 架构 + 静态链接，生成 `SHA256SUMS`
- **发布**：滚动 Release `backend-latest`，`gh release upload --clobber` 覆盖同名资产

---

## 10. 自动 / 手动构建工作流（本仓库）

`.github/workflows/build-fpk.yml` 负责在本仓库手动或自动构建 FPK。**当前默认仅手动触发**（自动触发逻辑已注释，需要时打开注释即可恢复）。

### 触发方式

| 方式 | 当前状态 | 说明 |
|---|---|---|
| `workflow_dispatch`（手动） | ✅ 启用 | 可指定 `fpk_version`（留空则跟随前端版本）、`port`、勾选 `force` 强制重建 |
| `schedule`（每小时） | 🔒 已注释 | 轮询 `xread` / `xread-kindle` 的 HEAD，任一变动或版本号变动才构建；无变动跳过。需要时打开 `on:` 段 `schedule` 两行注释 |
| `repository_dispatch` | 🔒 已注释 | 预留给源仓库主动通知；打开注释并按「实时触发」配置 PAT 后可用 |

> **启用自动构建**：编辑 `build-fpk.yml`，去掉 `on:` 段中 `# schedule:` 与 `# - cron:` 两行的注释即可；`workflow_dispatch` 必须保留（GitHub 要求 `on` 下至少有一个触发器）。

> 后端二进制由本工作流用 `--fetch-backend` 从 `backend-latest` Release 拉最新；xread 后端代码变动会先触发
> xread 仓库的 `build-backend.yml` 更新 Release，本工作流下一次运行时取到新二进制并重新打包。

### 版本号处理（关键）

- **FPK 版本 = `xread/frontend/package.json` 的 version**（单一来源）。前端版本号一改，下次构建
  FPK 版本自动跟随，产物名、`manifest.version`、设置页版本号同步更新。
- 手动触发可用 `fpk_version` 覆盖（仍须与前端 `package.json` 一致，否则 build.sh 校验拦截）。
- **后端 `appVersion` = 1.0.48**，由二进制自带，工作流不改写。
- **Kindle `frontVersion`** 随 `xread-kindle` 源码（`index.html` 的 `__XREAD_CONFIG__`）。

四类版本号对照见第 2 节。

### 首次启用检查

1. 确认 `Settings → Actions → General → Workflow permissions` 为 **Read and write**（回写 state / 发 Release 需要）。
2. 手动跑一次 `Run workflow` 验证；产物在 artifact 与 `fpk-v<版本>` Release。
3. `.github/build-state.json` 记录上次成功构建的源码 SHA，每次成功后自动回写。

### 实时触发（可选）

默认的每小时轮询已够用。若要 push 后立即构建，在两个源仓库各加一个 notify workflow，在目标路径
push 后调用本仓库的 dispatch API：

```bash
gh api repos/bingkuomiao/xread-fpk/dispatches \
  -f event_type=source-changed \
  -f client_payload='{"source":"xread","sha":"${{ github.sha }}"}'
```

需在源仓库配置一个有 `contents:write` 权限的 PAT（secret 名 `FPK_DISPATCH_TOKEN`）。不配置不影响定时轮询。

---

## 11. 回归测试

`tests/run-tests.sh` 是一套**轻量、离线、无第三方框架**的回归测试，覆盖打包工程里最容易回归、且可本地确定的关键逻辑。构建工作流的「预检回归测试」步骤会在每次构建前自动运行它；也可本地手动跑：

```bash
bash tests/run-tests.sh
# CI/自定义源码路径：
XREAD_SRC=/path/to/xread KINDLE_SRC=/path/to/xread-kindle bash tests/run-tests.sh
```

| 用例 | 检查内容 |
|---|---|
| T1 脚本语法 | `build.sh` / `fetch-backend.sh` 的 bash 语法、`patch_dist.py` 的 Python 语法 |
| T2 配置格式 | `manifest` 键值格式、`wizard/*.json`、`build-state.json` 可解析 |
| T3 版本一致性 | FPK / 前端 / Kindle / state 版本对齐（1.0.48.69）+ 后端 1.0.48 |
| T4 工作流有效性 | `build-fpk.yml` YAML 解析、仅手动触发、内嵌 shell 语法、自动触发已注释 |
| T5 patch_dist 幂等 | 首次注入 2 处、重复运行 0 处，且不误伤 `concurrentCount:24` |
| T6 后端拉取安全 | 本地模拟 Release：正常资产落地且 SHA 一致；篡改资产校验失败、拒绝替换目标目录 |

T6 用本地 HTTP 服务器模拟 GitHub Release，不依赖外网。退出码：全通过为 0，任一失败为 1。

---

## 12. 相关文档

- [文档中心](docs/README.md) — 全部说明文档的索引
- [Kindle 支持专文](docs/kindle/README.md) — Kindle 静态前端的访问方式、部署原理与更新方法
- [验证报告](docs/验证报告.md) — 本地端到端构建与验证记录
- [Win10 + WSL2 本地运行](docs/wsl2/README.md) — 部署 / 测试 / 开箱即用部署包制作
- [xread](https://github.com/bingkuomiao/xread) / [xread-kindle](https://github.com/bingkuomiao/xread-kindle) — 两大源码基线

## 13. 状态

已推送到 [bingkuomiao/xread-fpk](https://github.com/bingkuomiao/xread-fpk)（`main` 分支），含自动/手动构建工作流。
