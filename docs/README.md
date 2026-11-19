# XRead FPK 文档中心

本目录集中存放本仓库的全部说明文档。根目录 [README.md](../README.md) 是工程门面（应用说明 + 打包工程手册），以下是按主题归档的专文。

## 文档索引

| 主题 | 文档 | 说明 |
| --- | --- | --- |
| Kindle 前端 | [kindle/README.md](kindle/README.md) | Kindle 老浏览器前端的访问方式、部署原理、目录结构与更新方法 |
| Win10 + WSL2 本地运行 | [wsl2/README.md](wsl2/README.md) | 在 Windows 10 上通过 WSL2 运行 XRead：部署、测试排障、开箱即用部署包制作 |
| 验证记录 | [验证报告.md](验证报告.md) | 本地端到端构建与验证记录（打包流程固化过程） |

## Win10 + WSL2 子目录

| 文档 | 说明 |
| --- | --- |
| [wsl2/deploy.md](wsl2/deploy.md) | Win10 + WSL2 部署：环境、启动、本机/设备/Kindle 访问、重启后转发刷新清单 |
| [wsl2/testing.md](wsl2/testing.md) | 测试与排障：分层验证链路、"打开书很慢"排查、回归清单 |
| [wsl2/build-package.md](wsl2/build-package.md) | 开箱即用部署包 `xread-wsl2-<版本>.tar.gz` 制作方式 |
| [wsl2/build-wsl2-package.sh](wsl2/build-wsl2-package.sh) | 可复现的一键打包脚本 |
| [wsl2/xread-wsl2-lan.ps1](wsl2/xread-wsl2-lan.ps1) | 幂等热点端口转发脚本（重启后可重复运行） |

## 外部基线

- [xread](https://github.com/bingkuomiao/xread) — Rust 后端 + Vue3 前端源码
- [xread-kindle](https://github.com/bingkuomiao/xread-kindle) — Kindle / 手机 / PC 静态前端源码
