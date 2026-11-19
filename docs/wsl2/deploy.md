# Win10 + WSL2 部署

适用于没有 Linux 服务器、希望在 Windows 10 本机跑 XRead 的场景。采用 **WSL2 + musl 静态二进制** 方案：不依赖 glibc，Ubuntu 里解压即用，可让同一局域网（含 Kindle、手机）访问。

> 官方不提供原生 Windows exe（QuickJS 需 C 工具链交叉编译），WSL2 是最稳的本地方案。部署包与飞牛 fpk 用**完全相同的二进制与前端**，三端行为一致。

## 一、环境要求

| 项目 | 要求 |
| --- | --- |
| 系统 | Windows 10 64 位（19045 / 22H2 均可） |
| WSL | 已启用 WSL2，并安装 Ubuntu 发行版 |
| 发行版名 | 本文默认 `Ubuntu`（`wsl -d Ubuntu`），如不同请替换 |
| 架构 | amd64（x86_64）；arm64 机器会自动选用 `xread-arm64` |

确认 WSL2 正常：

```powershell
wsl -l -v
```

## 二、把部署包放进 Ubuntu

从资料库/Release 下载 `xread-wsl2-<版本>.tar.gz`，放到 `C:\Users\<你>\Downloads\`，在 Ubuntu 终端执行：

```bash
cp /mnt/c/Users/<你>/Downloads/xread-wsl2-<版本>.tar.gz ~/
tar -xzf xread-wsl2-<版本>.tar.gz
cd xread-wsl2
chmod +x start.sh bin/xread-amd64
```

> Windows 的 C 盘在 WSL 里是 `/mnt/c/`，D 盘是 `/mnt/d/`。

## 三、启动

```bash
./start.sh          # 前台运行，日志直接输出，Ctrl+C 停止
./start.sh -d       # 后台运行，日志写 storage/xread.log
./start.sh stop     # 停止后台进程
```

看到如下输出即启动成功（关键行是 `listening on 0.0.0.0:7777`）：

```
===================================================
 XRead 启动中
 架构: x86_64   二进制: xread-amd64
 访问: http://localhost:7777
===================================================
INFO  xread::app::bootstrap: listening on 0.0.0.0:7777
```

`start.sh` 会自动按架构选二进制、读取同目录 `.env`、把数据库和缓存都放在部署包的 `storage/` 下。

## 四、Windows 本机访问

浏览器打开 <http://localhost:7777>。WSL2 的 localhost 与 Windows 本机互通，无需查 WSL IP。

- 首次访问会引导注册管理员账户（`.env` 默认 `SECURE=true`）。
- 打不开时先确认：`.env` 里 `SERVER_HOST=0.0.0.0`（不是 `127.0.0.1`），且 XRead 正在运行。

## 五、配置项（`xread-wsl2/.env`，改后重启生效）

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `SERVER_HOST` | `0.0.0.0` | 监听地址；改成 `127.0.0.1` 则外部设备无法访问 |
| `SERVER_PORT` | `7777` | 端口；改后所有访问地址同步换端口 |
| `SECURE` | `true` | `false` = 免登录（仅建议本机自用） |
| `PUBLIC_READ` | `false` | `true` 时未登录访客可读（仅 `SECURE=true` 时有意义） |
| `REQUEST_TIMEOUT_SECS` | `15` | 书源抓取超时；书源站慢导致"打开书很慢"时可调小到 `8` |
| `LOG_LEVEL` | `info` | 排障时可设 `debug` |

数据（数据库、缓存、封面）都在 `xread-wsl2/storage/`，升级只替换 `bin/` 和 `web/`，保留该目录即可。

## 六、让手机 / Kindle 等设备访问（关键）

Win10 22H2 / 19045 **不支持 WSL 镜像模式**（那是 Win11 22H2+ 才有），走标准的 **Windows 端口转发（netsh portproxy）**。

### 网络拓扑

```
设备(192.168.137.x) ──连PC热点──> Windows 热点网卡(192.168.137.1)
                                      │  portproxy 转发
WSL2 Ubuntu(172.x.x.x) ──NAT虚拟网卡──> Windows 主机
```

- WSL 的 `172.x.x.x` 与热点网段 `192.168.137.x` 是两个独立网络。在 WSL 里 `ping 192.168.137.x` 丢包是**正常的**——真正的数据方向是反过来的：设备 → Windows → WSL。
- 因此设备访问的是 **PC 热点网卡地址**，不是 WSL IP。

### 一键配置（管理员 PowerShell）

以管理员身份打开 PowerShell，直接把 [xread-wsl2-lan.ps1](xread-wsl2-lan.ps1) 的内容整段粘贴执行（若提示禁止脚本，先执行 `Set-ExecutionPolicy -Scope Process Bypass`）。脚本会自动：取 WSL IP → 删除旧转发 → 添加新转发 → 放行防火墙 → 列出热点网卡 IP。

等价手写命令：

```powershell
$wslIp = (wsl -d Ubuntu -- hostname -I).Trim().Split(' ')[0]
netsh interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=7777 2>$null
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=7777 connectaddress=$wslIp connectport=7777
New-NetFirewallRule -DisplayName "XRead 7777" -Direction Inbound -Protocol TCP -LocalPort 7777 -Action Allow
netsh interface portproxy show v4tov4
```

### 设备访问地址

- 普通浏览器：<http://192.168.137.1:7777>
- **Kindle 阅读器**：<http://192.168.137.1:7777/xread>

> 部署包的 `web/dist/xread/` 就是 Kindle 前端，`config.js` 里 `address` 留空自动同源，API 会指向同主机的 `/reader3/...`，无需手填后端地址。刷新页面即为"更新文档"。

### 重启后必须重做（重要）

WSL2 每次启动都会重新分配虚拟 IP。PC 或 WSL 重启后，端口转发规则仍指向**旧 IP**，设备就打不开了。**防火墙规则是持久的，不用重加。**

重启后按此清单恢复：

1. 在 Ubuntu 启动服务：`cd ~/xread-wsl2 && ./start.sh -d`
2. 管理员 PowerShell 重跑一次热点脚本（刷新 WSL IP 转发）——这是幂等的，可重复运行。
3. 确认 Windows 移动热点处于开启状态，设备重新连一次热点。
4. Kindle 打开 <http://192.168.137.1:7777/xread>。

更多访问验证与"打开书很慢"的排查见 [WSL2 测试与排障](testing.md)。

## 七、开机自启（可选）

把热点脚本放到 Windows「任务计划程序」：创建基本任务 → 触发器「登录时」→ 操作「启动程序」→ 程序 `powershell.exe`，参数 `-NoProfile -ExecutionPolicy Bypass -File <脚本路径>`，并勾选"以最高权限运行"。WSL 里 XRead 可用 systemd 或登录脚本自启。

## 八、升级

下载新版部署包，在 Ubuntu 里解压到新目录，把旧目录的 `storage/` 复制过去，再启动：

```bash
tar -xzf xread-wsl2-<新版本>.tar.gz
cp -a xread-wsl2/storage/. xread-wsl2-new/storage/
cd xread-wsl2-new && ./start.sh -d
```

部署包的制作方式见 [开箱即用部署包制作](build-package.md)。
