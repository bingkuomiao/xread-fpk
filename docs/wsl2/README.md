# XRead FPK · Win10 + WSL2 本地运行文档

本目录收录在 Windows 10 上通过 WSL2 运行 XRead 的部署、测试与打包文档。二进制与前端和飞牛 fpk 包完全一致，只是换了启动与网络接入方式。

## 文档索引

| 文档 | 说明 |
| --- | --- |
| [deploy.md](deploy.md) | Win10 + WSL2 部署：环境要求、启动、本机/设备/Kindle 访问、重启后必做的转发刷新清单 |
| [testing.md](testing.md) | 测试与排障：分层验证链路、"登录成功但打开书很慢"排查、回归清单 |
| [build-package.md](build-package.md) | 开箱即用部署包 `xread-wsl2-<版本>.tar.gz` 的制作方式 |
| [build-wsl2-package.sh](build-wsl2-package.sh) | 可复现的一键打包脚本 |
| [xread-wsl2-lan.ps1](xread-wsl2-lan.ps1) | Windows 管理员 PowerShell 一键热点端口转发脚本（幂等） |

## 快速开始

1. 下载 `xread-wsl2-<版本>.tar.gz`，在 Ubuntu 解压并 `./start.sh -d` 启动。
2. Windows 浏览器开 <http://localhost:7777> 验证本机。
3. 管理员 PowerShell 执行 [xread-wsl2-lan.ps1](xread-wsl2-lan.ps1) 配置端口转发。
4. Kindle 打开 <http://192.168.137.1:7777/xread>。
5. **PC/WSL 重启后**：重新启动 XRead + 重跑热点脚本刷新 IP 转发（详见 [deploy.md](deploy.md) 第六节）。
