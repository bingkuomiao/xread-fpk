#!/usr/bin/env bash
# 从 xread 仓库的 GitHub Release `backend-latest` 拉取最新后端二进制。
#
# 该 Release 由 xread/.github/workflows/build-backend.yml 在后端代码变更时自动发布，
# 包含 xread-amd64 / xread-arm64 / SHA256SUMS 三个资产，永远指向最近一次成功构建。
#
# 用法：
#   ./tools/fetch-backend.sh                     # 拉取到本地 backend/ 并校验
#   BACKEND_DIR=/path ./tools/fetch-backend.sh   # 指定目标目录
#   GITHUB_TOKEN=ghp_xxx ./tools/fetch-backend.sh  # 用 token（私有仓/避免限流，可选）
#
# 环境变量：
#   XREAD_REPO   仓库 slug（默认 bingkuomiao/xread）
#   RELEASE_TAG  发布标签（默认 backend-latest）
#   BACKEND_DIR  二进制落地目录（默认脚本所在工程根的 backend/）
#   GITHUB_API   API 根地址（默认 https://api.github.com，可指向自托管/本地模拟）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${XREAD_REPO:-bingkuomiao/xread}"
TAG="${RELEASE_TAG:-backend-latest}"
BACKEND_DIR="${BACKEND_DIR:-$ROOT/backend}"
API_HOST="${GITHUB_API:-https://api.github.com}"
API="${API_HOST}/repos/${REPO}/releases/tags/${TAG}"

log() { echo ">> $*"; }
die() { echo "错误: $*" >&2; exit 1; }

# 下载带重试（此环境网络易抖动）；公开 Release 资产走匿名下载，不用 auth header。
# 用法: dl <url> <out> <描述>
dl() {
    curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 \
         --connect-timeout 15 --max-time 180 \
         -o "$2" "$1" || die "下载 $3 失败（网络问题，可重跑）"
}

command -v curl >/dev/null || die "缺少 curl"
command -v python3 >/dev/null || die "缺少 python3"

AUTH=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
    AUTH=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

log "查询 Release: ${REPO}@${TAG}"
META="$(curl -fsSL "${AUTH[@]}" "$API")" || die "无法读取 Release（检查仓库/标签/网络，或设置 GITHUB_TOKEN）"

# 解析各资产下载 URL（用 python 避免 jq 依赖）
read -r URL_AMD64 URL_ARM64 URL_SUM <<EOF
$(printf '%s' "$META" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assets={a["name"]: a["browser_download_url"] for a in d.get("assets",[])}
need=["xread-amd64","xread-arm64","SHA256SUMS"]
missing=[n for n in need if n not in assets]
if missing:
    sys.exit("缺少资产: "+", ".join(missing))
print(assets["xread-amd64"], assets["xread-arm64"], assets["SHA256SUMS"])
')
EOF

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
log "下载 xread-amd64"
dl "$URL_AMD64" "$TMP/xread-amd64" "xread-amd64"
log "下载 xread-arm64"
dl "$URL_ARM64" "$TMP/xread-arm64" "xread-arm64"
dl "$URL_SUM" "$TMP/SHA256SUMS" "SHA256SUMS"

log "校验 SHA256"
( cd "$TMP" && sha256sum -c SHA256SUMS ) || die "SHA256 校验失败，拒绝替换本地基线"

# 静态 ELF 二次校验（防止下到错误资产）
for a in amd64 arm64; do
    file "$TMP/xread-$a" | grep -q 'ELF 64-bit' || die "xread-$a 不是 64 位 ELF"
    file "$TMP/xread-$a" | grep -q 'static' || die "xread-$a 不是静态链接"
done

mkdir -p "$BACKEND_DIR"
for a in amd64 arm64; do
    cp "$TMP/xread-$a" "$BACKEND_DIR/xread-$a"
    chmod +x "$BACKEND_DIR/xread-$a"
done
cp "$TMP/SHA256SUMS" "$BACKEND_DIR/SHA256SUMS"

echo
echo "========== 后端二进制已更新 =========="
echo "目标目录: $BACKEND_DIR"
( cd "$BACKEND_DIR" && sha256sum xread-amd64 xread-arm64 )
echo "来源: ${REPO}@${TAG}"
