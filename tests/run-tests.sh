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
#   T7 打包产物        dist 双包存在、版本文件名与 manifest 对齐、fpk 内含版本注入
#   T8 changelog       manifest changelog 版本标注与 version 字段一致
#   T9 挂载点唯一性    Kindle 静态前端只有 /xread 单一挂载点，无 app/kindle 副本回归
#   T10 后端二进制     双架构静态 ELF、可执行
#   T11 kindle 兼容性  调用 tests/kindle-compat.sh（ES5/UA/对接契约/配置/版本自洽）
#
# 用法：bash tests/run-tests.sh
# 退出码：0 全部通过；1 有失败。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

XREAD_SRC="${XREAD_SRC:-$ROOT/../xread}"
KINDLE_SRC="${KINDLE_SRC:-$ROOT/../xread-kindle}"
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
import json
n = 0
for line in open('manifest', encoding='utf-8'):
    if '=' in line and not line.lstrip().startswith('#'):
        k, v = line.split('=', 1)
        assert k.strip().islower() and k.strip().replace('_', '').isalpha(), repr(k)
        assert v.strip(), repr(line)
        n += 1
assert n > 0
json.load(open('wizard/config', encoding='utf-8'))
json.load(open('wizard/install', encoding='utf-8'))
json.load(open('.github/build-state.json', encoding='utf-8'))
PY
[ $? -eq 0 ] && ok "manifest 键值 + wizard JSON + build-state.json 格式" || bad "manifest / wizard / build-state 格式"

# ---------- T3 版本一致性 ----------
sec "T3 版本一致性（前端 / kindle / fpk / 后端）"
python3 - <<'PY' >/dev/null
import json, os
def ver(path, key):
    return json.load(open(path, encoding='utf-8'))[key]
def manver():
    for line in open('manifest', encoding='utf-8'):
        if line.startswith('version'):
            return line.split('=', 1)[1].strip()
fpk = manver()
fe  = ver(os.path.join(os.environ['XREAD_SRC'], 'frontend/package.json'), 'version')
st  = json.load(open('.github/build-state.json', encoding='utf-8'))['fpk_version']
kindle_html = open(os.path.join(os.environ['KINDLE_SRC'], 'index.html'), encoding='utf-8').read()
kd = kindle_html.split('"frontVersion":"')[1].split('"')[0]
assert fpk == fe == st == kd, 'FPK/前端/state/Kindle 版本不一致: ' + '/'.join([fpk, fe, st, kd])
assert len(fpk.split('.')) == 4 and fpk.startswith('1.0.48.'), 'FPK 版本格式非预期: ' + fpk
cargo = ''
for line in open(os.path.join(os.environ['XREAD_SRC'], 'Cargo.toml'), encoding='utf-8'):
    if line.startswith('version'):
        cargo = line.split('=', 1)[1].strip().strip('"')
assert cargo == '1.0.48', '后端 Cargo.toml 版本非预期: ' + cargo
assert 'appVersion 1.0.48' in open('manifest', encoding='utf-8').read(), 'manifest changelog 未标注 appVersion 1.0.48'
PY
[ $? -eq 0 ] && ok "四类版本号对齐（fpk/前端/state/kindle 一致，后端=1.0.48）" || bad "四类版本号一致性"

# ---------- T4 工作流有效性 ----------
sec "T4 工作流有效性（build-fpk.yml）"
python3 - <<'PY'
import yaml, subprocess, tempfile, os
p = '.github/workflows/build-fpk.yml'
d = yaml.safe_load(open(p, encoding='utf-8'))
on_key = 'on' if 'on' in d else True
triggers = list(d[on_key].keys())
assert triggers == ['workflow_dispatch'], '触发器异常，应仅手动: ' + str(triggers)
assert 'build' in d['jobs']
fails = []
for jn, job in d['jobs'].items():
    for st in job['steps']:
        if 'run' in st:
            with tempfile.NamedTemporaryFile('w', suffix='.sh', delete=False) as f:
                f.write(st['run']); fp = f.name
            if subprocess.run(['bash', '-n', fp], capture_output=True).returncode:
                fails.append(st.get('name', '?'))
            os.unlink(fp)
assert not fails, 'shell 语法失败: ' + str(fails)
print("WORKFLOW_OK")
PY
if [ $? -eq 0 ] && python3 -c "
import yaml
d=yaml.safe_load(open('.github/workflows/build-fpk.yml',encoding='utf-8'))
s=open('.github/workflows/build-fpk.yml',encoding='utf-8').read()
assert '  # schedule:' in s and '  # repository_dispatch:' in s
" 2>/dev/null; then
    ok "YAML/触发器(仅手动)/shell 块，且自动触发已注释"
else
    bad "工作流 YAML 或 shell 语法"
fi

# ---------- T5 patch_dist 幂等性 ----------
sec "T5 patch_dist 幂等性"
FX="$TMP/fixture"
mkdir -p "$FX/assets"
echo '<html><head></head><body>x</body></html>' > "$FX/index.html"
echo 'var a={concurrentCount:8}; var b={concurrentCount:8}; var c={concurrentCount:24};' > "$FX/assets/app.js"
R1=$(python3 tools/patch_dist.py "$FX" 2>&1); RC1=$?
R2=$(python3 tools/patch_dist.py "$FX" 2>&1); RC2=$?
EXPR_N=$(grep -o 'concurrentCount:(window.__XREAD_CONFIG__?.cacheConcurrency||4)' "$FX/assets/app.js" | wc -l)
PLACE_N=$(grep -o 'window.__XREAD_CONFIG__' "$FX/index.html" | wc -l)
if [ $RC1 -eq 0 ] && [ $RC2 -eq 0 ] && [ "$EXPR_N" -eq 2 ] && [ "$PLACE_N" -eq 1 ] && echo "$R2" | grep -q '替换 0 处'; then
    ok "首次注入 2 处 / 重复运行 0 处 / 占位唯一 / 不误伤 concurrentCount:24"
else
    bad "patch_dist 幂等性（rc1=$RC1 rc2=$RC2 expr=$EXPR_N placeholder=$PLACE_N）"
    echo "$R1" | sed 's/^/       /'
    echo "$R2" | sed 's/^/       /'
fi

# ---------- T6 后端拉取的 SHA 校验保护 ----------
sec "T6 后端拉取安全（篡改资产必须拒绝替换）"
MOCK="$TMP/mock-release"
mkdir -p "$MOCK/repos/bingkuomiao/xread/releases/tags" "$MOCK/assets"
cp backend/xread-amd64 backend/xread-arm64 "$MOCK/assets/"
( cd "$MOCK/assets" && sha256sum xread-amd64 xread-arm64 > SHA256SUMS )
PORT=""
for p in 18931 18932 18933 18934 18935; do
    if ! (echo >/dev/tcp/127.0.0.1/$p) >/dev/null 2>&1; then PORT=$p; break; fi
done
[ -n "$PORT" ] || { bad "T6 无可用端口"; PORT=18931; }
python3 - "$PORT" > "$MOCK/repos/bingkuomiao/xread/releases/tags/backend-latest" <<'PY'
import json, sys
base = 'http://127.0.0.1:' + sys.argv[1] + '/assets'
print(json.dumps({"tag_name": "backend-latest", "assets": [
    {"name": "xread-amd64", "browser_download_url": base + "/xread-amd64"},
    {"name": "xread-arm64", "browser_download_url": base + "/xread-arm64"},
    {"name": "SHA256SUMS",   "browser_download_url": base + "/SHA256SUMS"},
]}))
PY
python3 -m http.server "$PORT" --directory "$MOCK" >/dev/null 2>&1 &
MOCK_PID=$!
READY=0
for i in 1 2 3 4 5 6 7 8 9 10; do
    if curl -fsS --max-time 1 "http://127.0.0.1:$PORT/repos/bingkuomiao/xread/releases/tags/backend-latest" >/dev/null 2>&1; then
        READY=1; break
    fi
    sleep 0.5
done
[ "$READY" -eq 1 ] || bad "T6 mock 服务器未就绪"
BA="$TMP/backend-ok"
GITHUB_API="http://127.0.0.1:$PORT" BACKEND_DIR="$BA" bash tools/fetch-backend.sh >/dev/null 2>&1
RA=$?
( cd "$BA" 2>/dev/null && sha256sum -c SHA256SUMS >/dev/null 2>&1 ); SA=$?
echo corrupted >> "$MOCK/assets/xread-amd64"
BB="$TMP/backend-bad"; mkdir -p "$BB"; echo SENTINEL > "$BB/xread-amd64"
GITHUB_API="http://127.0.0.1:$PORT" BACKEND_DIR="$BB" bash tools/fetch-backend.sh >/dev/null 2>&1
RB=$?
SENT=$(cat "$BB/xread-amd64" 2>/dev/null)
if [ $RA -eq 0 ] && [ $SA -eq 0 ] && [ $RB -ne 0 ] && [ "$SENT" = "SENTINEL" ]; then
    ok "正常资产落地且 SHA 一致；篡改资产校验失败、拒绝替换、目标目录未被动"
else
    bad "后端拉取安全（正常 rc=$RA sha=$SA；篡改 rc=$RB 哨兵=$SENT）"
fi
kill "$MOCK_PID" 2>/dev/null; MOCK_PID=""

# ---------- T7 打包产物 ----------
sec "T7 打包产物完整性（双包存在 / 版本文件名 / BUILD_INFO 注入）"
python3 - <<'PY' >/dev/null
import os, tarfile, io
ver = ''
for line in open('manifest', encoding='utf-8'):
    if line.startswith('version'):
        ver = line.split('=', 1)[1].strip()
fpk = 'dist/xread-native-' + ver + '.fpk'
wsl = 'dist/xread-wsl2-' + ver + '.tar.gz'
assert os.path.isfile(fpk), '缺少 FPK 产物: ' + fpk
assert os.path.isfile(wsl), '缺少 WSL2 产物: ' + wsl
assert os.path.getsize(fpk) > 1024*1024, 'FPK 体积异常'
assert os.path.getsize(wsl) > 1024*1024, 'WSL2 体积异常'
with tarfile.open(fpk, 'r:gz') as t:
    names = t.getnames()
    for must in ('manifest','app.tgz','cmd/main','ICON.PNG'):
        assert must in names, 'FPK 缺少关键条目: ' + must
    app = t.extractfile('app.tgz').read()
with tarfile.open(fileobj=io.BytesIO(app), mode='r:*') as t2:
    bi = [n for n in t2.getnames() if n.endswith('BUILD_INFO')]
    assert bi, 'FPK app.tgz 内缺少 BUILD_INFO'
    info = t2.extractfile(bi[0]).read().decode()
assert ('VERSION=' + ver) in [ln.strip() for ln in info.splitlines()], 'BUILD_INFO VERSION 与 manifest 不符'
assert 'SOURCE_MODE=xread+xread-kindle' in info, 'BUILD_INFO 缺少来源溯源'
PY
[ $? -eq 0 ] && ok "dist 双包齐全且体积正常；FPK 关键条目与 BUILD_INFO.VERSION 注入正确" || bad "打包产物完整性"

# ---------- T8 changelog 版本标注 ----------
sec "T8 manifest changelog 版本标注一致性"
python3 - <<'PY' >/dev/null
ver = ''
cl = ''
for line in open('manifest', encoding='utf-8'):
    if line.startswith('version'):
        ver = line.split('=', 1)[1].strip()
    if line.startswith('changelog'):
        cl = line.split('=', 1)[1].strip()
assert cl.startswith('v' + ver + '：'), 'changelog 未以 v' + ver + ' 开头'
assert '前端版本 ' + ver in cl, 'changelog 前端版本标注与 manifest 不符'
assert 'appVersion 1.0.48' in cl, 'changelog 缺少 appVersion 1.0.48 标注'
PY
[ $? -eq 0 ] && ok "changelog 以 v{version} 开头，前端版本/appVersion 标注一致" || bad "manifest changelog 版本标注"

# ---------- T9 挂载点唯一性 ----------
sec "T9 Kindle 前端单挂载点（防 app/kindle 副本回归）"
python3 - <<'PY' >/dev/null
import os
sh = open('build.sh', encoding='utf-8').read()
assert 'KINDLE_SRC/.' in sh and 'app/web/dist/xread/' in sh, '构建脚本缺少 web/dist/xread 挂载'
code_lines = [ln for ln in sh.splitlines() if not ln.lstrip().startswith('#')]
assert not any('app/kindle' in ln for ln in code_lines), 'build.sh 仍有向 app/kindle 复制的逻辑'
assert not os.path.exists('app/kindle'), '工作区出现 app/kindle 实体目录（去重回归）'
PY
[ $? -eq 0 ] && ok "Kindle 前端仅挂 web/dist/xread，无 app/kindle 副本回归" || bad "Kindle 单挂载点去重检查"

# ---------- T10 后端二进制 ----------
sec "T10 后端二进制（双架构静态 ELF + 可执行）"
python3 - <<'PY' >/dev/null
import os
elf = bytes([0x7f, 0x45, 0x4c, 0x46])
for arch in ('xread-amd64', 'xread-arm64'):
    p = os.path.join('backend', arch)
    assert os.path.isfile(p), '缺少后端二进制: ' + p
    assert os.access(p, os.X_OK), '后端二进制不可执行: ' + p
    with open(p, 'rb') as f:
        head = f.read(20)
    assert head[:4] == elf, arch + ' 非 ELF'
    assert head[4] == 2, arch + ' 非 64 位'
PY
[ $? -eq 0 ] && ok "backend 下 amd64/arm64 均为 64 位 ELF 且可执行" || bad "后端二进制检查"

# ---------- T11 Kindle 兼容性 ----------
sec "T11 Kindle 代码兼容性检查"
if [ -f tests/kindle-compat.sh ]; then
    bash tests/kindle-compat.sh
    [ $? -eq 0 ] && ok "Kindle 兼容性检查全部通过" || bad "Kindle 兼容性检查存在失败项"
else
    bad "缺少 tests/kindle-compat.sh"
fi

# ---------- 汇总 ----------
echo
echo "============================================================"
echo " 结果: $PASS 通过 / $FAIL 失败"
echo "============================================================"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
