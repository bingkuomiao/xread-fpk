#!/usr/bin/env bash
# 组装 Win10 + WSL2 开箱即用部署包 xread-wsl2-<版本>.tar.gz
#
# 两种用法：
#   1) 从 GitHub Release backend-latest 拉静态二进制 + 本地前端构建：
#        OWNER_REPO=bingkuomiao/xread VERSION=1.0.48.90 bash scripts/build-wsl2-package.sh
#   2) 完全离线，指定已备好的原料目录：
#        BIN_DIR=./bin WEB_DIST=./frontend/dist KINDLE_DIR=./xread-kindle VERSION=1.0.48.90 \
#          bash scripts/build-wsl2-package.sh
#
# 产物放在仓库根目录：xread-wsl2-<版本>.tar.gz

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

VERSION="${VERSION:-$(grep -m1 '"version"' frontend/package.json | sed -E 's/.*"([^"]+)".*/\1/')}"
OWNER_REPO="${OWNER_REPO:-bingkuomiao/xread}"
PKG_NAME="xread-wsl2"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

ROOT_DIR="$STAGE/$PKG_NAME"
mkdir -p "$ROOT_DIR/bin" "$ROOT_DIR/web/dist" "$ROOT_DIR/storage/assets"

echo "==> 版本: $VERSION"
echo "==> 暂存目录: $STAGE"

# ---------- 1. 二进制 ----------
if [ -n "${BIN_DIR:-}" ]; then
  echo "==> 使用本地二进制: $BIN_DIR"
  cp "$BIN_DIR/xread-amd64"  "$ROOT_DIR/bin/"
  cp "$BIN_DIR/xread-arm64"  "$ROOT_DIR/bin/"
else
  BASE="https://github.com/${OWNER_REPO}/releases/download/backend-latest"
  echo "==> 从 $BASE 拉取静态二进制"
  curl -fL "$BASE/xread-amd64" -o "$ROOT_DIR/bin/xread-amd64"
  curl -fL "$BASE/xread-arm64" -o "$ROOT_DIR/bin/xread-arm64"
  # 校验（若 Release 提供 SHA256SUMS）
  if curl -fsSL "$BASE/SHA256SUMS" -o "$STAGE/SHA256SUMS"; then
    (cd "$ROOT_DIR/bin" && sha256sum -c "$STAGE/SHA256SUMS")
  fi
fi
chmod +x "$ROOT_DIR/bin/xread-amd64" "$ROOT_DIR/bin/xread-arm64"
for f in xread-amd64 xread-arm64; do
  file "$ROOT_DIR/bin/$f" | grep -q 'ELF 64-bit' || { echo "ERROR: $f 不是 64 位 ELF"; exit 1; }
  file "$ROOT_DIR/bin/$f" | grep -q 'static'     || { echo "ERROR: $f 不是静态链接"; exit 1; }
done

# ---------- 2. Vue3 前端 ----------
if [ -n "${WEB_DIST:-}" ]; then
  echo "==> 使用本地前端产物: $WEB_DIST"
  cp -r "$WEB_DIST"/. "$ROOT_DIR/web/dist/"
else
  echo "==> 构建 Vue3 前端"
  (cd "$REPO_ROOT/frontend" && npm ci && npm run build)
  cp -r "$REPO_ROOT/frontend/dist"/. "$ROOT_DIR/web/dist/"
fi

# ---------- 3. Kindle 前端 ----------
if [ -n "${KINDLE_DIR:-}" ]; then
  echo "==> 使用本地 Kindle 前端: $KINDLE_DIR"
else
  echo "==> 克隆 Kindle 前端"
  KINDLE_DIR="$STAGE/xread-kindle"
  git clone --depth 1 https://github.com/bingkuomiao/xread-kindle.git "$KINDLE_DIR"
fi
cp -r "$KINDLE_DIR"/. "$ROOT_DIR/web/dist/xread/"
# 去掉开发态文件，减小体积
rm -rf "$ROOT_DIR/web/dist/xread/.git" "$ROOT_DIR/web/dist/xread/.github"

# ---------- 4. start.sh 与 .env ----------
cat > "$ROOT_DIR/start.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
BASE_DIR="$(pwd)"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64)  BIN="$BASE_DIR/bin/xread-amd64" ;;
  aarch64|arm64) BIN="$BASE_DIR/bin/xread-arm64" ;;
  *) echo "不支持的架构: $ARCH" >&2; exit 1 ;;
esac
mkdir -p "$BASE_DIR/storage/assets"
if [ -f "$BASE_DIR/.env" ]; then
  set -a; source "$BASE_DIR/.env"; set +a
fi
export SERVER_HOST="${SERVER_HOST:-0.0.0.0}"
export SERVER_PORT="${SERVER_PORT:-7777}"
export DATABASE_URL="${DATABASE_URL:-sqlite:$BASE_DIR/storage/reader.db?mode=rwc}"
export STORAGE_DIR="${STORAGE_DIR:-$BASE_DIR/storage}"
export ASSETS_DIR="${ASSETS_DIR:-$BASE_DIR/storage/assets}"
export WEB_ROOT="${WEB_ROOT:-$BASE_DIR/web/dist}"
export LOG_LEVEL="${LOG_LEVEL:-info}"
export SECURE="${SECURE:-true}"
export PUBLIC_READ="${PUBLIC_READ:-false}"
echo "==================================================="
echo " XRead 启动中"
echo " 架构: $ARCH   二进制: $(basename "$BIN")"
echo " 访问: http://localhost:${SERVER_PORT}"
echo " 数据: $BASE_DIR/storage"
echo "==================================================="
start_fg() { exec "$BIN"; }
start_bg() {
  if [ -f "$BASE_DIR/storage/xread.pid" ] && kill -0 "$(cat "$BASE_DIR/storage/xread.pid")" 2>/dev/null; then
    echo "XRead 已在运行"; exit 1
  fi
  nohup "$BIN" >"$BASE_DIR/storage/xread.log" 2>&1 &
  echo $! >"$BASE_DIR/storage/xread.pid"
  echo "已后台启动 PID $(cat "$BASE_DIR/storage/xread.pid")"
}
stop_bg() {
  if [ -f "$BASE_DIR/storage/xread.pid" ]; then
    kill "$(cat "$BASE_DIR/storage/xread.pid")" 2>/dev/null || true
    rm -f "$BASE_DIR/storage/xread.pid"; echo "已停止"
  else echo "未找到 PID 文件"; fi
}
case "${1:-}" in
  -d|--daemon) start_bg ;;
  stop)        stop_bg ;;
  *)           start_fg ;;
esac
EOF
chmod +x "$ROOT_DIR/start.sh"

cat > "$ROOT_DIR/.env" <<'EOF'
SERVER_HOST=0.0.0.0
SERVER_PORT=7777
LOG_LEVEL=info
SECURE=true
PUBLIC_READ=false
REQUEST_TIMEOUT_SECS=15
INVITE_CODE=
USER_LIMIT=50
EOF

# ---------- 5. 打包 ----------
OUT="$REPO_ROOT/${PKG_NAME}-${VERSION}.tar.gz"
tar -czf "$OUT" -C "$STAGE" "$PKG_NAME"

echo "==> 完成: $OUT"
echo "==> 大小: $(du -h "$OUT" | cut -f1)"
echo "==> 清单:"
tar -tvzf "$OUT" | grep -E 'bin/|start.sh|\.env$|index.html' | head -20
