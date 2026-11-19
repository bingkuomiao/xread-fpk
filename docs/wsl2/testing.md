# WSL2 测试与排障

记录 Win10 + WSL2 部署方式的完整验证链路与常见故障排查，适用于"登录成功但打开书很慢"等场景。

## 一、分层验证链路

一个问题先定位在哪一层，再往下查。按顺序逐层验证：

| 层 | 验证动作 | 通过标志 |
| --- | --- | --- |
| ① WSL 服务 | Ubuntu 里 `curl -I http://localhost:7777` | 返回 `HTTP/1.1 200`（或 401，鉴权开启时） |
| ② Windows 本机 | Windows 浏览器开 `http://localhost:7777` | 能打开登录页 → 服务与本机互通正常 |
| ③ 端口转发 | 管理员 PowerShell `netsh interface portproxy show v4tov4` | 有 `0.0.0.0 7777 → <当前WSL IP> 7777` |
| ④ 局域网设备 | 设备浏览器开 `http://192.168.137.1:7777` | 能打开 → 转发 + 防火墙 + 热点均正常 |
| ⑤ Kindle 前端 | Kindle 开 `http://192.168.137.1:7777/xread` | 能打开书架/阅读界面 |

关键点：**② 通过、④ 不通过 → 问题在端口转发或防火墙**，不在 XRead 本身。

## 二、验证服务真的在监听

启动日志里认准这一行：

```
INFO  xread::app::bootstrap: listening on 0.0.0.0:7777
DEBUG starting axum::serve on 0.0.0.0:7777
```

若 `.env` 的 `SERVER_HOST=127.0.0.1`，这里会显示 `127.0.0.1:7777`，外部设备一定访问不到，改回 `0.0.0.0` 并重启。

## 三、登录成功但打开书很慢

这是最常见的现象，结论：**瓶颈在"WSL → 书源网站"的外网抓取，不在 Kindle / 热点 / 端口转发**。理由是登录只走本地后端（很快），而打开书要按书源规则实时抓取外网内容。

启动/访问日志里的典型证据：

```
DEBUG fetch executing GET request to: http://www.buxia.la/xiaoshuo/250906/
ERROR Internal(... operation timed out)   // 某书源站超时
response failed 500  latency=45667 ms     // 单次抓取卡了 ~45 秒
```

### 排查步骤

在 Ubuntu 终端对慢速书源站做测速：

```bash
# 强制 IPv4
time curl -4 -o /dev/null -s -w "%{http_code}  %{time_total}s\n" http://<书源域名>/<路径>

# 默认解析（不强制）
time curl -o /dev/null -s -w "%{http_code}  %{time_total}s\n" http://<书源域名>/<路径>

# DNS 解析耗时
time nslookup <书源域名>
```

### 两类原因与处理

**① IPv6 优先导致超时**（Linux 访问国内站常见坑：先试 IPv6，不通就干等几十秒才回退 IPv4）

判断：上面第 1 条（`-4`）秒回、第 2 条卡十几秒。处理：

```bash
# 临时生效
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
```

永久生效把这两行写入 `/etc/sysctl.conf`。不影响 IPv4 端口转发，设备访问照常。

**② 书源站本身慢 / 挂了 / 有反爬**（如日志里反复超时的 `buxia.la`）

- 在书源管理里禁用或删除总超时的源，换可用的源。
- 缩短超时快速失败：`.env` 里 `REQUEST_TIMEOUT_SECS=15` 改为 `8`，重启生效。

> XRead 会缓存抓过的内容，首次慢、再开同一本通常变快。若每次都慢，多半是那次抓取就失败了（书源站问题）。

## 四、设备打不开的常见原因

| 现象 | 检查项 |
| --- | --- |
| Windows 本机 `localhost:7777` 也打不开 | XRead 没运行，或 `.env` 的 `SERVER_HOST` 不是 `0.0.0.0` |
| 本机能开、设备打不开 | 端口转发是否指向**当前** WSL IP；防火墙 7777 入站规则是否存在；热点是否允许"设备间/访问主机" |
| 之前能访问、重启后失效 | WSL IP 变了，重跑热点脚本刷新转发（脚本幂等） |
| 抓取大量 `fetch ... timed out` | 见上一节"打开书很慢" |
| 返回 500 Internal Server Error | 多为某个书源站抓取失败，非服务故障；结合日志定位具体 URL |

## 五、回归测试清单

改动前端或升级部署包后，按此顺序回归：

1. `cd frontend && npm run build && npm test`（前端构建与单测；已知 147/148，唯一失败为既有 `local-txt` 刷新计数用例，与本次改动无关）。
2. 替换部署包 `web/dist/`，`./start.sh -d` 重启。
3. 按第一节 ①→⑤ 逐层验证。
4. Kindle 上打开 <http://192.168.137.1:7777/xread>，验证书架、目录、正文、翻页、书源切换。
5. 重启 PC 后按 [WSL2 部署](deploy.md) 第六节清单恢复，确认转发刷新后仍可访问。
