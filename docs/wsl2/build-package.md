# 开箱即用部署包制作

本文说明如何把 XRead 制作成 Win10 + WSL2 开箱即用的部署包 `xread-wsl2-<版本>.tar.gz`。二进制与飞牛 fpk 完全一致，只是换了启动与网络接入方式。

## 一、部署包结构

```
xread-wsl2/
├── bin/
│   ├── xread-amd64        # musl 静态二进制（x86_64）
│   └── xread-arm64        # musl 静态二进制（aarch64）
├── web/
│   └── dist/              # Vue3 前端构建产物
│       └── xread/         # Kindle 前端（同源挂 /xread）
├── start.sh               # 启动脚本（自动选架构、读 .env）
├── .env                   # 默认配置
└── storage/               # 运行时生成：数据库、缓存、日志
    └── assets/
```

关键点：二进制是 `static-pie` 链接，不依赖 glibc 或任何系统库，Ubuntu 里 `chmod +x` 后即可运行。

## 二、三种原料的来源

| 原料 | 来源 | 说明 |
| --- | --- | --- |
| `bin/xread-amd64`、`bin/xread-arm64` | GitHub Actions `build-backend.yml` 的滚动 Release `backend-latest` | musl 静态编译，含 `SHA256SUMS` |
| `web/dist/`（Vue3 前端） | 本仓库 `frontend/` 执行 `npm run build` | 产物在 `frontend/dist` |
| `web/dist/xread/`（Kindle 前端） | `bingkuomiao/xread-kindle` 仓库 | 静态站点，整目录拷入 |

### 1. 取静态二进制

`build-backend.yml` 在后端代码变更时交叉编译双架构并发布到稳定 tag，地址与 commit 无关：

```bash
BASE=https://github.com/<owner>/<repo>/releases/download/backend-latest
curl -fL "$BASE/xread-amd64"  -o bin/xread-amd64
curl -fL "$BASE/xread-arm64"  -o bin/xread-arm64
curl -fL "$BASE/SHA256SUMS"   -o /tmp/SHA256SUMS
cd bin && sha256sum -c /tmp/SHA256SUMS   # 校验
file xread-amd64   # 应显示 ELF 64-bit ... static
```

> `<owner>/<repo>` 换成实际仓库（如 `bingkuomiao/xread`）。若 Release 未启用，也可本地用 `cross build --release --target x86_64-unknown-linux-musl` 编译。

### 2. 构建 Vue3 前端

```bash
cd frontend
npm ci
npm run build
# 产物在 frontend/dist，拷为部署包的 web/dist
```

### 3. 加入 Kindle 前端

```bash
git clone https://github.com/bingkuomiao/xread-kindle.git /tmp/xread-kindle
cp -r /tmp/xread-kindle web/dist/xread
```

`config.js` 里 `address` 保持留空（自动同源），Kindle 访问 `/xread` 时 API 自动指向 `/reader3/...`，无需改后端。

## 三、启动脚本 `.env`

`start.sh` 负责选架构、读 `.env`、设置默认路径并 `exec` 二进制，核心片段：

```bash
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64)  BIN="$BASE_DIR/bin/xread-amd64" ;;
  aarch64|arm64) BIN="$BASE_DIR/bin/xread-arm64" ;;
esac
export SERVER_HOST="${SERVER_HOST:-0.0.0.0}"
export SERVER_PORT="${SERVER_PORT:-7777}"
export WEB_ROOT="${WEB_ROOT:-$BASE_DIR/web/dist}"
exec "$BIN"
```

配套 `.env`（默认值）：

```ini
SERVER_HOST=0.0.0.0
SERVER_PORT=7777
LOG_LEVEL=info
SECURE=true
PUBLIC_READ=false
REQUEST_TIMEOUT_SECS=15
INVITE_CODE=
USER_LIMIT=50
```

完整 `start.sh` 支持 `./start.sh`（前台）、`-d`（后台）、`stop`（停止）。

## 四、可复现构建脚本

仓库提供 `scripts/build-wsl2-package.sh`，一键完成上述组装、校验与打包：

```bash
# 用 Release 二进制（推荐）
OWNER_REPO=bingkuomiao/xread VERSION=1.0.48.90 \
  bash scripts/build-wsl2-package.sh

# 或用本地已备好的二进制/前端（离线打包）
BIN_DIR=/path/to/bin WEB_DIST=/path/to/dist KINDLE_DIR=/path/to/xread-kindle \
  VERSION=1.0.48.90 bash scripts/build-wsl2-package.sh
```

产物：`xread-wsl2-<版本>.tar.gz`（约 25MB）。脚本会先做完整性检查，再打包，最后列出清单。

## 五、校验与解包核验

打包后务必核验，避免交付后才发现缺文件：

```bash
# 查看清单与大小
tar -tvzf xread-wsl2-<版本>.tar.gz | head -30

# 解包到临时目录并确认关键文件
mkdir -p /tmp/verify && tar -xzf xread-wsl2-<版本>.tar.gz -C /tmp/verify
ls -l /tmp/verify/xread-wsl2/bin/xread-amd64
file /tmp/verify/xread-wsl2/bin/xread-amd64   # ELF 64-bit static
test -f /tmp/verify/xread-wsl2/web/dist/index.html && echo "Vue 前端 OK"
test -f /tmp/verify/xread-wsl2/web/dist/xread/index.html && echo "Kindle 前端 OK"
```

## 六、发布

1. 把部署包上传到资料库 / Release，版本号与源码、前端 `frontVersion` 保持一致。
2. 更新构建状态文件（如 `.github/build-state.json`）、`frontend/package.json`、`index.html` 中的版本号。
3. 老包可在生成新包后清理，仅保留最新版下载卡片。
4. 每次升级保留说明文档与热点脚本，指向 [WSL2 部署](deploy.md) 与 [WSL2 测试与排障](testing.md)。
