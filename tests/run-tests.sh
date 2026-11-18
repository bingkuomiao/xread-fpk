#!/usr/bin/env bash
# xread-fpk 打包工程回归测试（轻量、离线、无第三方框架）
#
# 覆盖打包工程里最容易回归、且可本地确定的关键逻辑：
#   T1 脚本语法        build.sh / fetch-backend.sh / patch_dist.py
#   T2 配置格式        manifest 键值、wizard JSON、build-state.json
#   T3 版本一致性      四类版本号（前端/kindle/fpk/后端）互相对齐
#   T4 工作流有效性    build-fpk.yml YAML + 触发器 + 内嵌 shell 语法
#   T5 patch_dist 幂等 首次注入 2 处、重复运行 0 处，且不误伤搜索并发
#   T6 后端拉取安全    SHA256 校验失败时拒绝替换目标目录（本地模拟 Release）
#
# 用法：bash tests/run-tests.sh
# 退出码：0 全部通过；1 有失败。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# 源仓库路径：本地默认 ../xread 与 ../kabi-reader；CI 中由工作流传入 src/xread 等
XREAD_SRC="${XREAD_SRC:-$ROOT/../xread}"
KINDLE_SRC="${KINDLE_SRC:-$ROOT/../kabi-reader}"
export XREAD_SRC KINDLE_SRC

PASS=0
FAIL=0
ok()   { echo "  [PASS] $*"; PASS=$((PASS+1)); }
bad()  { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
sec()  { echo; echo "=== $* ==="; }

TMP="$(mktemp -d)"
MOCK_PID=""
cleanup() {
    [ -n "$MOCK_PID" ] && kill "$MOCK_PID" 2>/dev/null || true
    rm -rf "$TMP"
}
trap cleanup EXIT

echo "============================================================"
echo " xread-fpk 回归测试"
echo " 工程根目录: $ROOT"
echo "============================================================"

# ---------- T1 脚本语法 ----------
sec "T1 脚本语法"
if bash -n build.sh 2>/dev/null; then ok "build.sh 语法"; else bad "build.sh 语法"; fi
if bash -n tools/fetch-backend.sh 2>/dev/null; then ok "fetch-backend.sh 语法"; else bad "fetch-backend.sh 语法"; fi
if python3 -c "import ast; ast.parse(open('tools/patch_dist.py',encoding='utf-8').read())" 2>/dev/null; then
    ok "patch_dist.py 语法"
else
    bad "patch_dist.py 语法"
fi

# ---------- T2 配置格式 ----------
sec "T2 配置格式"
python3 - <<'PY' >/dev/null
import json, re
# manifest: 键为小写下划线 + 若干空格，值非空
n = 0
for line in open('manifest', encoding='utf-8'):
    if '=' in line and not line.lstrip().startswith('#'):
        k, v = line.split('=', 1)
        assert re.match(r'^[a-z_]+ +$', k), repr(k)
        assert v.strip(), repr(line)
        n += 1
assert n > 0
# wizard / state JSON 可解析
json.load(open('wizard/config', encoding='utf-8'))
json.load(open('wizard/install', encoding='utf-8'))
json.load(open('.github/build-state.json', encoding='utf-8'))
PY
[ $? -eq 0 ] && ok "manifest 键值 + wizard JSON + build-state.json 格式" \
               || bad "manifest / wizard / build-state 格式"

# ---------- T3 版本一致性 ----------
sec "T3 版本一致性（前端 / kindle / fpk / 后端）"
python3 - <<'PY' >/dev/null
import json, re, os
def ver(path, key):
    return json.load(open(path, encoding='utf-8'))[key]
fpk = re.search(r'^version\s*=\s*(\S+)', open('manifest', encoding='utf-8').read(), re.M).group(1)
fe  = ver(os.path.join(os.environ['XREAD_SRC'], 'frontend/package.json'), 'version')
st  = json.load(open('.github/build-state.json', encoding='utf-8'))['fpk_version']
kindle_html = open(os.path.join(os.environ['KINDLE_SRC'], 'index.html'), encoding='utf-8').read()
kd = re.search(r'"frontVersion"\s*:\s*"([^"]+)"', kindle_html).group(1)
assert fpk == fe == st == kd, f'FPK/前端/state/Kindle 版本不一致: {fpk}/{fe}/{st}/{kd}'
assert fpk == '1.0.48.69', f'FPK 版本非预期: {fpk}'
# 后端版本：Cargo.toml = 1.0.48；appVersion 由二进制自带，manifest 仅在 changelog 文案中标注
cargo = re.search(r'^version\s*=\s*"([^"]+)"', open(os.path.join(os.environ['XREAD_SRC'], 'Cargo.toml'), encoding='utf-8').read(), re.M).group(1)
assert cargo == '1.0.48', f'后端 Cargo.toml 版本非预期: {cargo}'
assert 'appVersion 1.0.48' in open('manifest', encoding='utf-8').read(), 'manifest changelog 未标注 appVersion 1.0.48'
PY
[ $? -eq 0 ] && ok "四类版本号对齐（fpk/前端/state/kindle=1.0.48.69，后端=1.0.48）" \
               || bad "四类版本号一致性"

# ---------- T4 工作流有效性 ----------
sec "T4 工作流有效性（build-fpk.yml）"
python3 - <<'PY'
import yaml, subprocess, tempfile, os
p = '.github/workflows/build-fpk.yml'
d = yaml.safe_load(open(p, encoding='utf-8'))
on_key = 'on' if 'on' in d else True
triggers = list(d[on_key].keys())
# 当前设计：自动触发已注释，仅手动
assert triggers == ['workflow_dispatch'], f'触发器异常，应仅手动: {triggers}'
assert 'build' in d['jobs']
# 内嵌 shell 语法
fails = []
for jn, job in d['jobs'].items():
    for st in job['steps']:
        if 'run' in st:
            with tempfile.NamedTemporaryFile('w', suffix='.sh', delete=False) as f:
                f.write(st['run']); fp = f.name
            if subprocess.run(['bash', '-n', fp], capture_output=True).returncode:
                fails.append(st.get('name', '?'))
            os.unlink(fp)
assert not fails, f'shell 语法失败: {fails}'
print("WORKFLOW_OK")
PY
if [ $? -eq 0 ] && python3 -c "
import yaml
d=yaml.safe_load(open('.github/workflows/build-fpk.yml',encoding='utf-8'))
k='on' if 'on' in d else True
s=open('.github/workflows/build-fpk.yml',encoding='utf-8').read()
assert '  # schedule:' in s and '  # repository_dispatch:' in s
" 2>/dev/null; then
    ok "YAML/触发器(仅手动)/5 个 shell 块，且自动触发已注释"
else
    bad "工作流 YAML 或 shell 语法"
fi

# ---------- T5 patch_dist 幂等性 ----------
sec "T5 patch_dist 幂等性"
FX="$TMP/fixture"
mkdir -p "$FX/assets"
printf '<html><head></head><body>x</body></html>\n' > "$FX/index.html"
printf 'var a={concurrentCount:8}; var b={concurrentCount:8}; var c={concurrentCount:24};\n' > "$FX/assets/app.js"
R1=$(python3 tools/patch_dist.py "$FX" 2>&1); RC1=$?
R2=$(python3 tools/patch_dist.py "$FX" 2>&1); RC2=$?
EXPR_N=$(grep -o 'concurrentCount:(window.__XREAD_CONFIG__?.cacheConcurrency||4)' "$FX/assets/app.js" | wc -l)
PLACE_N=$(grep -o 'window.__XREAD_CONFIG__' "$FX/index.html" | wc -l)
if [ $RC1 -eq 0 ] && [ $RC2 -eq 0 ] && [ "$EXPR_N" -eq 2 ] && [ "$PLACE_N" -eq 1 ] \
   && echo "$R2" | grep -q '替换 0 处'; then
    ok "首次注入 2 处 / 重复运行 0 处 / 占位唯一 / 不误伤 concurrentCount:24"
else
    bad "patch_dist 幂等性（rc1=$RC1 rc2=$RC2 expr=$EXPR_N placeholder=$PLACE_N）"
    echo "$R1" | sed 's/^/       /'
    echo "$R2" | sed 's/^/       /'
fi

# ---------- T6 后端拉取的 SHA 校验保护（本地模拟 Release，不联网）----------
sec "T6 后端拉取安全（篡改资产必须拒绝替换）"
MOCK="$TMP/mock-release"
mkdir -p "$MOCK/repos/bingkuomiao/xread/releases/tags" "$MOCK/assets"
cp backend/xread-amd64 backend/xread-arm64 "$MOCK/assets/"
( cd "$MOCK/assets" && sha256sum xread-amd64 xread-arm64 > SHA256SUMS )
# 选一个当前未被占用的固定端口
PORT=""
for p in 18931 18932 18933 18934 18935; do
    if ! (echo >/dev/tcp/127.0.0.1/$p) >/dev/null 2>&1; then PORT=$p; break; fi
done
[ -n "$PORT" ] || { bad "T6 无可用端口"; PORT=18931; }
python3 - "$PORT" > "$MOCK/repos/bingkuomiao/xread/releases/tags/backend-latest" <<'PY'
import json, sys
base = f"http://127.0.0.1:{sys.argv[1]}/assets"
print(json.dumps({"tag_name": "backend-latest", "assets": [
    {"name": "xread-amd64", "browser_download_url": base + "/xread-amd64"},
    {"name": "xread-arm64", "browser_download_url": base + "/xread-arm64"},
    {"name": "SHA256SUMS",   "browser_download_url": base + "/SHA256SUMS"},
]}))
PY
# 直接后台启动（不加子 shell 包裹），确保 MOCK_PID 就是 python 进程本身
python3 -m http.server "$PORT" --directory "$MOCK" >/dev/null 2>&1 &
MOCK_PID=$!
# 等服务器就绪（最多约 5 秒）
READY=0
for i in 1 2 3 4 5 6 7 8 9 10; do
    if curl -fsS --max-time 1 "http://127.0.0.1:$PORT/repos/bingkuomiao/xread/releases/tags/backend-latest" >/dev/null 2>&1; then
        READY=1; break
    fi
    sleep 0.5
done
[ "$READY" -eq 1 ] || bad "T6 mock 服务器未就绪"
# 场景 A：正常资产 → 成功落地且 SHA 一致
BA="$TMP/backend-ok"
GITHUB_API="http://127.0.0.1:$PORT" BACKEND_DIR="$BA" \
    bash tools/fetch-backend.sh >/dev/null 2>&1
RA=$?
( cd "$BA" 2>/dev/null && sha256sum -c SHA256SUMS >/dev/null 2>&1 ); SA=$?
# 场景 B：篡改资产 → 校验失败、退出非 0、哨兵文件不被替换
echo corrupted >> "$MOCK/assets/xread-amd64"
BB="$TMP/backend-bad"; mkdir -p "$BB"; echo SENTINEL > "$BB/xread-amd64"
GITHUB_API="http://127.0.0.1:$PORT" BACKEND_DIR="$BB" \
    bash tools/fetch-backend.sh >/dev/null 2>&1
RB=$?
SENT=$(cat "$BB/xread-amd64" 2>/dev/null)
if [ $RA -eq 0 ] && [ $SA -eq 0 ] && [ $RB -ne 0 ] && [ "$SENT" = "SENTINEL" ]; then
    ok "正常资产落地且 SHA 一致；篡改资产校验失败、拒绝替换、目标目录未被动"
else
    bad "后端拉取安全（正常 rc=$RA sha=$SA；篡改 rc=$RB 哨兵=$SENT）"
fi
kill "$MOCK_PID" 2>/dev/null; MOCK_PID=""

# ---------- 汇总 ----------
echo
echo "============================================================"
echo " 结果: $PASS 通过 / $FAIL 失败"
echo "============================================================"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
