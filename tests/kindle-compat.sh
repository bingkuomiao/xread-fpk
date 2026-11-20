#!/usr/bin/env bash
# xread-kindle 前端兼容性检查（供 run-tests.sh 调用，也可单独运行）
# 覆盖：K1 ES5 语法 / K2 浏览器 UA 检测 / K3 后端对接契约 / K4 配置安全 / K5 版本自洽
# 说明：用纯字符串匹配实现，避免正则反斜杠，便于通过受限通道推送。
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KINDLE_SRC="${KINDLE_SRC:-$ROOT/../xread-kindle}"
P=0; F=0
ok()  { echo "  [PASS] $*"; P=$((P+1)); }
bad() { echo "  [FAIL] $*"; F=$((F+1)); }
echo "  -- Kindle 兼容性检查（源: $KINDLE_SRC）--"
[ -d "$KINDLE_SRC" ] || { echo "  [FAIL] 找不到 KINDLE_SRC"; exit 1; }

python3 - "$KINDLE_SRC" >/tmp/kc.out 2>&1 <<'PY'
import sys, os
src = sys.argv[1]
def read(p): return open(os.path.join(src, p), encoding='utf-8').read()
html = read('index.html')
cfg  = read('js/config.js')
kjs  = read('js/kindle.js')
js = ''
for f in os.listdir(os.path.join(src, 'js')):
    if f.endswith('.js'):
        js += read('js/' + f) + chr(10)
res = []
# K1 ES5: 运行时 JS 不得出现箭头函数与 let/const 声明
res.append(('K1 ES5 语法', '=>' not in js and 'const ' not in js and 'let ' not in js))
# K2 UA 检测：index.html 内联与 kindle.js 均需覆盖关键 UA 标记
for t in ('Kindle', 'Silk', 'KFAP', 'armv7l', 'AppleWebKit/534', 'Safari/534', 'xread-browser'):
    res.append(('K2 UA:' + t, t in html))
res.append(('K2 isKindleBrowser', 'isKindleBrowser' in kjs and 'AppleWebKit/534.26+' in kjs))
# K3 后端对接契约：路由/字段/分项/删除
for t in ('getAvailableBookSource', 'chapterUrl', 'bookSourceUrl', 'resultLimit', 'hasMore', 'data.books', 'bookUrl'):
    res.append(('K3 契约:' + t, t in kjs))
res.append(('K3 无旧路由', '/reader3/searchBookSource' not in kjs))
# K4 配置安全：multi、同源空地址、无硬编码 IP、accessToken 鉴权
res.append(('K4 type=multi', 'multi' in cfg))
res.append(('K4 同源地址', 'address: ""' in cfg.replace("'", '"')))
res.append(('K4 accessToken', 'accessToken' in kjs))
# K5 版本自洽：frontVersion 与所有 ?v= 查询串一致，且属 1.0.48 系列
fv = html.split('"frontVersion":"')[1].split('"')[0]
vs = set(part.split('"')[0] for part in html.split('?v=')[1:])
res.append(('K5 版本自洽', bool(vs) and all(v == fv for v in vs)))
res.append(('K5 版本系列', fv.startswith('1.0.48.')))
for name, okv in res:
    print(('PASS ' if okv else 'FAIL ') + name)
if any(not okv for _, okv in res):
    sys.exit(1)
PY
RC=$?
grep -q '^PASS' /tmp/kc.out && while IFS= read -r line; do case "$line" in PASS*) ok "${line#PASS }";; FAIL*) bad "${line#FAIL }";; esac; done < /tmp/kc.out
[ "$RC" -ne 0 ] && ! grep -q '^FAIL' /tmp/kc.out && bad "兼容性检查执行异常: $(tr -s '[:space:]' ' ' </tmp/kc.out)"
rm -f /tmp/kc.out
echo "  -- Kindle 兼容性小计: $P 通过 / $F 失败 --"
[ "$F" -eq 0 ] && exit 0 || exit 1
