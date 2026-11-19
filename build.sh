#!/usr/bin/env bash
# xread-fpk —— 从两大源码基线的最新产物统一打包飞牛 fnOS .fpk
# 仓库：https://github.com/bingkuomiao/xread-fpk
#
# 源码基线（唯一来源，打包工程本身不再内嵌前后端源码）：
#   • xread        : Rust 后端（二进制）+ Vue3 前端（源码，需编译）
#   • xread-kindle : Kindle / 手机 / PC 静态前端（源码即产物，直接复制）
#
# 本工程只保留：打包壳（manifest/cmd/config/wizard/ICON）、后端二进制基线、
# fnpack 打包器、运行时配置注入工具。不编译 Rust（后端二进制从 backend/ 取，
# 可用 --fetch-backend 从 xread 的 backend-latest Release 拉最新产物）。
#
# 用法：
#   ./build.sh                          # 用默认版本+端口打包到 dist/
#   ./build.sh --fetch-backend          # 打包前从 backend-latest Release 拉最新后端二进制
#   ./build.sh --pull                   # 打包前对两个源码仓库执行 git pull 更新
#   ./build.sh --pull --fetch-backend   # 前端源码 + 后端二进制都拉最新
#   XREAD_VERSION=1.0.48.93 ./build.sh  # 指定版本（写入 manifest / 前端版本号检查 / 文件名）
#   XREAD_PORT=7778 ./build.sh          # 指定服务端口
#   XREAD_OUT=/path ./build.sh          # 指定产物输出目录
#
# 相关环境变量：
#   XREAD_SRC   xread 仓库本地路径        （默认 ../xread）
#   KINDLE_SRC  xread-kindle 本地路径     （默认 ../xread-kindle）
#   SKIP_FE=1   跳过前端编译，复用上次 frontend-dist/ （调试用）
#   SKIP_WSL2=1 跳过 WSL2 包（默认与 FPK 同时产出）
#   GITHUB_TOKEN  拉取后端时传递（可选，避免 API 限流/私有仓）
#
# 出包约定：每次构建默认同时产出两个同源包（二进制/前端完全一致）：
#   dist/xread-native-<版本>.fpk      —— 飞牛 fnOS 原生安装包
#   dist/xread-wsl2-<版本>.tar.gz     —— Win10 + WSL2 开箱即用部署包
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XREAD_SRC="${XREAD_SRC:-$ROOT/../xread}"
KINDLE_SRC="${KINDLE_SRC:-$ROOT/../xread-kindle}"
VERSION="${XREAD_VERSION:-1.0.48.93}"
PORT="${XREAD_PORT:-7777}"
OUT_DIR="${XREAD_OUT:-$ROOT/dist}"
FNPACK="$ROOT/tools/fnpack"
DO_PULL=0
FETCH_BACKEND=0
SKIP_FE="${SKIP_FE:-}"

for arg in "$@"; do
    case "$arg" in
        --pull) DO_PULL=1 ;;
        --fetch-backend) FETCH_BACKEND=1 ;;
        -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
        *) echo "未知参数: $arg" >&2; exit 1 ;;
    esac
done

[[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )) || {
    echo "错误：XREAD_PORT 必须是 1-65535 的数字，当前 '$PORT'" >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][A-Za-z0-9.]+)?$ ]] || {
    echo "错误：XREAD_VERSION 需为 x.y.z 形式，当前 '$VERSION'" >&2; exit 1; }

log() { echo ">> $*"; }
die() { echo "错误: $*" >&2; exit 1; }

# ---------- 0a. 拉取最新后端二进制（可选）----------
if [ "$FETCH_BACKEND" = 1 ]; then
    log "从 xread@backend-latest Release 拉取最新后端二进制"
    [ -x "$ROOT/tools/fetch-backend.sh" ] || die "缺少 tools/fetch-backend.sh"
    bash "$ROOT/tools/fetch-backend.sh" || die "拉取后端二进制失败"
fi

# ---------- 0. 前置检查 ----------
log "检查源码与工具"
[ -d "$XREAD_SRC/frontend/src" ]    || die "找不到 xread 前端源码: $XREAD_SRC/frontend/src"
[ -f "$XREAD_SRC/frontend/package.json" ] || die "找不到 $XREAD_SRC/frontend/package.json"
[ -f "$KINDLE_SRC/index.html" ]      || die "找不到 xread-kindle 前端: $KINDLE_SRC/index.html"
[ -f "$ROOT/backend/xread-amd64" ]   || die "缺少后端二进制基线: backend/xread-amd64"
[ -f "$ROOT/backend/xread-arm64" ]   || die "缺少后端二进制基线: backend/xread-arm64"
[ -x "$FNPACK" ]                     || die "缺少打包器: tools/fnpack"
command -v node >/dev/null || die "缺少 node"
command -v npm  >/dev/null || die "缺少 npm"
command -v python3 >/dev/null || die "缺少 python3"

if [ "$DO_PULL" = 1 ]; then
    log "更新源码基线（git pull --ff-only）"
    git -C "$XREAD_SRC" pull --ff-only   || die "xread 拉取失败"
    git -C "$KINDLE_SRC" pull --ff-only  || die "xread-kindle 拉取失败"
fi
XREAD_COMMIT="$(git -C "$XREAD_SRC" rev-parse HEAD 2>/dev/null || echo unknown)"
KINDLE_COMMIT="$(git -C "$KINDLE_SRC" rev-parse HEAD 2>/dev/null || echo unknown)"
log "xread      @ ${XREAD_COMMIT:0:12}"
log "xread-kindle @ ${KINDLE_COMMIT:0:12}"

# ---------- 1. 编译 xread Vue3 前端 ----------
FE_DIST="$ROOT/frontend-dist"
if [ "$SKIP_FE" = 1 ] && [ -f "$FE_DIST/index.html" ]; then
    log "SKIP_FE=1：复用已有前端产物 $FE_DIST"
else
    log "编译 xread Vue3 前端"
    [ -d "$XREAD_SRC/frontend/node_modules" ] || {
        log "node_modules 缺失，npm install"
        ( cd "$XREAD_SRC/frontend" && npm install )
    }
    # 前端版本号由 package.json 注入 __APP_VERSION__；打包版本必须与之一致。
    FE_VER="$(python3 -c "import json;print(json.load(open('$XREAD_SRC/frontend/package.json'))['version'])")"
    [ "$FE_VER" = "$VERSION" ] || die "版本不一致：xread 前端 package.json=$FE_VER，请求打包版本=$VERSION（请同步两者）"
    ( cd "$XREAD_SRC/frontend" && npm run build )
    [ -f "$XREAD_SRC/frontend/dist/index.html" ] || die "前端构建未产出 index.html"
    rm -rf "$FE_DIST"
    cp -a "$XREAD_SRC/frontend/dist" "$FE_DIST"
    log "前端编译完成：$(find "$FE_DIST" -type f | wc -l) 个文件"
fi

# ---------- 2. 注入运行时配置（构建产物层，不改源码）----------
log "注入 fnOS 运行时配置占位（cacheConcurrency / testSourceTimeout）"
python3 "$ROOT/tools/patch_dist.py" "$FE_DIST"

# ---------- 3. 组装干净构建目录 ----------
log "组装构建目录"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
for d in config cmd wizard app/bin app/ui/images app/web/dist/xread; do
    mkdir -p "$STAGE/$d"
done
cp "$ROOT/manifest" "$ROOT/ICON.PNG" "$ROOT/ICON_256.PNG" "$STAGE/"
cp -a "$ROOT/config/."  "$STAGE/config/"
cp -a "$ROOT/cmd/."     "$STAGE/cmd/"
cp -a "$ROOT/wizard/."  "$STAGE/wizard/"
# 后端二进制（已验证静态 ELF 基线）
cp "$ROOT/backend/xread-amd64" "$STAGE/app/bin/xread-amd64"
cp "$ROOT/backend/xread-arm64" "$STAGE/app/bin/xread-arm64"
# 桌面入口壳：app/ui/config + 图标
cp -a "$ROOT/app/ui/." "$STAGE/app/ui/"
# Vue3 前端 -> app/web/dist
cp -a "$FE_DIST/." "$STAGE/app/web/dist/"
# Kindle 静态前端 -> app/kindle 且挂到 web 根的 /xread 子路径
cp -a "$KINDLE_SRC/." "$STAGE/app/web/dist/xread/"
mkdir -p "$STAGE/app/kindle"
cp -a "$KINDLE_SRC/." "$STAGE/app/kindle/"
# 去掉 kindle 源仓库自带的 .git 等无关文件
rm -rf "$STAGE/app/web/dist/xread/.git" "$STAGE/app/kindle/.git" \
       "$STAGE/app/kindle/out" "$STAGE/app/web/dist/xread/out" \
       "$STAGE/app/kindle/diagnose.html" "$STAGE/app/web/dist/xread/diagnose.html"
# BUILD_INFO（溯源）
if [ "$FETCH_BACKEND" = 1 ]; then
    BACKEND_SRC="xread@backend-latest Release (SHA256 verified)"
else
    BACKEND_SRC="local backend/ baseline (prebuilt static ELF)"
fi
cat > "$STAGE/BUILD_INFO" <<EOF
SOURCE_MODE=xread+xread-kindle (product-based packaging)
XREAD_COMMIT=$XREAD_COMMIT
KINDLE_COMMIT=$KINDLE_COMMIT
BACKEND=$BACKEND_SRC
NODE=$(node --version 2>/dev/null)
NPM=$(npm --version 2>/dev/null)
BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
VERSION=$VERSION
EOF
cp "$STAGE/BUILD_INFO" "$STAGE/app/BUILD_INFO"
log "组装完成：$(find "$STAGE" -type f | wc -l) 个文件"

# ---------- 4. 注入端口 / 版本 ----------
log "注入参数：port=$PORT version=$VERSION"
python3 - "$STAGE" "$PORT" "$VERSION" <<'PY'
import re, sys, pathlib
stage, port, version = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]

p = stage / 'manifest'
s = p.read_text(encoding='utf-8')
s, n1 = re.subn(r'(?m)^(version\s*=\s*)\S+', lambda m: m.group(1) + version, s)
s, n2 = re.subn(r'(?m)^(service_port\s*=\s*)\S+', lambda m: m.group(1) + port, s)
if n1 != 1 or n2 != 1:
    raise SystemExit('manifest version/service_port 替换失败')
p.write_text(s, encoding='utf-8')

def edit(rel, old, new, required=True):
    q = stage / rel
    t = q.read_text(encoding='utf-8')
    if old not in t and required:
        raise SystemExit(f'替换失败: {rel} :: {old!r}')
    q.write_text(t.replace(old, new), encoding='utf-8')

edit('app/ui/config', '"port": "7777"', f'"port": "{port}"')
edit('cmd/main', 'SERVICE_PORT="7777"', f'SERVICE_PORT="{port}"')
PY

# ---------- 5. 校验 ----------
log "校验产物"
python3 - "$STAGE" "$VERSION" <<'PY'
import json, pathlib, re, struct, subprocess, sys
stage, version = pathlib.Path(sys.argv[1]), sys.argv[2]
required = ['manifest','ICON.PNG','ICON_256.PNG','BUILD_INFO',
            'config/privilege','config/resource','cmd/main','cmd/_write_env.sh',
            'wizard/install','wizard/config','app/ui/config',
            'app/ui/images/icon_64.png','app/ui/images/icon_256.png',
            'app/bin/xread-amd64','app/bin/xread-arm64',
            'app/web/dist/index.html','app/kindle/index.html',
            'app/web/dist/xread/index.html']
for r in required:
    if not (stage / r).is_file():
        raise SystemExit(f'缺少必需文件: {r}')
for r in ['config/privilege','config/resource','app/ui/config','wizard/install','wizard/config']:
    json.loads((stage / r).read_text(encoding='utf-8'))

idx = (stage / 'app/web/dist/index.html').read_text(encoding='utf-8')
if 'window.__XREAD_CONFIG__' not in idx:
    raise SystemExit('前端缺少运行时配置占位')
if '"testSourceTimeout":120' not in idx:
    raise SystemExit('运行时配置 testSourceTimeout 默认值不是 120')

# 版本号注入检查（设置页显示）
all_js = ''.join(p.read_text(encoding='utf-8') for p in (stage/'app/web/dist/assets').glob('*.js'))
if f'v{version}' not in all_js:
    raise SystemExit(f'前端产物找不到 v{version}（版本号未注入设置页）')

# 双架构静态 ELF
for a, machine in [('amd64',62),('arm64',183)]:
    b = (stage/'app'/'bin'/f'xread-{a}').read_bytes()
    if b[:4] != b'\x7fELF' or struct.unpack_from('<H', b, 18)[0] != machine:
        raise SystemExit(f'ELF 架构错误: {a}')
    if 'INTERP' in subprocess.run(['readelf','-l',str(stage/'app'/'bin'/f'xread-{a}')],
                                   capture_output=True,text=True).stdout:
        raise SystemExit(f'非静态链接: {a}')

m = {}
for line in (stage/'manifest').read_text(encoding='utf-8').splitlines():
    if '=' in line and not line.lstrip().startswith('#'):
        k,v = line.split('=',1); m[k.strip()] = v.strip()
if m.get('version') != version:
    raise SystemExit('manifest version 与请求版本不一致')
print('  校验通过：文件齐全 / JSON 合法 / 运行时配置 / 版本号 / 双架构静态 ELF')
PY

# ---------- 6. 打包 ----------
log "fnpack build"
( cd "$STAGE" && "$FNPACK" build )
FPK="$(find "$STAGE" -maxdepth 1 -name '*.fpk' -type f | head -n1)"
[ -n "$FPK" ] || die "fnpack 未生成 fpk"
mkdir -p "$OUT_DIR"
DEST="$OUT_DIR/xread-native-${VERSION}.fpk"
cp "$FPK" "$DEST"
echo
echo "========== FPK 完成 =========="
echo "产物: $DEST ($(du -h "$DEST" | cut -f1))"

# ---------- 8. WSL2 部署包（与 FPK 同源，默认同时产出）----------
# 复用同一批原料：backend/ 二进制 + frontend-dist/ 前端 + KINDLE_SRC Kindle 前端。
# 约定：后续每次新版本更新，同时给出 .fpk 与 wsl2 .tar.gz 两个包。
WSL2_SCRIPT="$ROOT/scripts/build-wsl2-package.sh"
if [ "${SKIP_WSL2:-0}" = 1 ]; then
    log "SKIP_WSL2=1：跳过 WSL2 包"
elif [ ! -f "$WSL2_SCRIPT" ]; then
    echo "警告：缺少 $WSL2_SCRIPT，跳过 WSL2 包" >&2
else
    log "构建 WSL2 部署包（与 FPK 同源）"
    BIN_DIR="$ROOT/backend" \
    WEB_DIST="$ROOT/frontend-dist" \
    KINDLE_SRC_REAL="$KINDLE_SRC" \
    KINDLE_DIR="$KINDLE_SRC" \
    VERSION="$VERSION" \
    WSL2_OUT="$OUT_DIR/xread-wsl2-${VERSION}.tar.gz" \
      bash "$WSL2_SCRIPT" || die "WSL2 包构建失败"
fi

echo
echo "========== 完成 =========="
echo "FPK  : $DEST ($(du -h "$DEST" | cut -f1))"
[ "${SKIP_WSL2:-0}" = 1 ] || echo "WSL2 : $OUT_DIR/xread-wsl2-${VERSION}.tar.gz ($(du -h "$OUT_DIR/xread-wsl2-${VERSION}.tar.gz" 2>/dev/null | cut -f1))"
echo "源码: xread@${XREAD_COMMIT:0:12} + xread-kindle@${KINDLE_COMMIT:0:12}"
