#!/usr/bin/env python3
"""对上游「纯净构建产物」打运行时并发补丁，不修改任何前端源码。

背景：
  fnOS 安装向导提供「批量缓存并发数」（默认 4）。上游源码把该值硬编码为
  `concurrentCount: 8`（CacheManager.vue / CacheLibraryModal.vue）。为了让向导值
  生效又保持上游源码零改动，改为在 vite/rolldown 构建完成后、打包进 fpk 之前，
  对 dist 做两处机械替换：

  1. index.html 的 </head> 前插入占位脚本
       <script>window.__XREAD_CONFIG__={"cacheConcurrency":4,"testSourceTimeout":120};</script>
     cmd/main 启动时会按向导值替换其中的数字（导航请求在 Service Worker 中是
     network-first，每次刷新都能拿到新值；JS 里不含具体数值，缓存无影响）。
  2. 压缩 JS 里恰好 2 处 `concurrentCount:8` 改为读取全局配置：
       concurrentCount:(window.__XREAD_CONFIG__?.cacheConcurrency||4)
     只匹配批量缓存的 `concurrentCount:8`；搜索用的 `concurrentCount:24`、
     参数缺省 `concurrentCount??8`、`concurrentCount:Ye` 等均不动。

幂等：已打过补丁的 dist 再次运行会跳过，不会产生重复脚本或二次替换。

用法：
    python3 tools/patch_dist.py <dist目录>
    # 典型：python3 tools/patch_dist.py ../upstream/frontend/dist
"""
from __future__ import annotations

import glob
import os
import re
import sys

PLACEHOLDER = '<script>window.__XREAD_CONFIG__={"cacheConcurrency":4,"testSourceTimeout":120};</script>'
EXPR = "concurrentCount:(window.__XREAD_CONFIG__?.cacheConcurrency||4)"
# 只匹配 `:8` 且后面不是数字或小数点，避免误伤 24 / 8.5 / ??8
PATTERN = re.compile(r"concurrentCount\s*:\s*8(?![0-9.])")


def patch(dist: str) -> int:
    index_html = os.path.join(dist, "index.html")
    if not os.path.isfile(index_html):
        raise SystemExit(f"找不到 {index_html}")

    html = open(index_html, encoding="utf-8").read()
    if "window.__XREAD_CONFIG__" in html:
        print("index.html 已含运行时配置，跳过注入")
    else:
        if "</head>" not in html:
            raise SystemExit("index.html 缺少 </head>，无法注入")
        html = html.replace(
            "</head>",
            "    <!-- fnOS 运行时配置：cmd/main 启动时按向导值替换 -->\n"
            "    " + PLACEHOLDER + "\n  </head>",
            1,
        )
        open(index_html, "w", encoding="utf-8").write(html)
        print("已注入 index.html 运行时配置占位")

    total = 0
    for path in sorted(glob.glob(os.path.join(dist, "assets", "*.js"))):
        src = open(path, encoding="utf-8").read()
        if EXPR in src:  # 该文件已打过补丁
            continue
        out, n = PATTERN.subn(EXPR, src)
        if n:
            open(path, "w", encoding="utf-8").write(out)
            print(f"  {os.path.basename(path)}: 替换 {n} 处")
            total += n

    # 校验：首次运行必须恰好 2 处；重复运行为 0（幂等）
    if total not in (0, 2):
        raise SystemExit(f"异常：并发补丁替换 {total} 处，期望 0（已打过）或 2（首次）")

    # 最终一致性校验
    final_html = open(index_html, encoding="utf-8").read()
    assert "window.__XREAD_CONFIG__" in final_html, "index.html 缺少运行时配置"
    assert '"testSourceTimeout":120' in final_html, "index.html 缺少 testSourceTimeout 占位"
    all_js = "".join(
        open(f, encoding="utf-8").read()
        for f in glob.glob(os.path.join(dist, "assets", "*.js"))
    )
    assert all_js.count(EXPR) == 2, f"运行时读取表达式数量异常: {all_js.count(EXPR)}"
    assert "concurrentCount:24" in all_js, "搜索并发被误改"

    print(f"完成：并发补丁替换 {total} 处（首次应 2，重复运行应 0）")
    return total


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "dist"
    patch(os.path.abspath(target))
