# XRead-kindle（Kindle 老浏览器前端）

本包在 `app/web/dist/xread/` 内置了一份**兼容 XRead 后端 `/reader3/*` API 的静态阅读前端**（源码基线为
[bingkuomiao/xread-kindle](https://github.com/bingkuomiao/xread-kindle)，由 `kabi-reader` 改造而来），
用于 **Kindle 等老 WebKit 浏览器**访问。它由 Rust 后端以静态文件形式在 `/xread` 路径下提供，
与手机 / PC 使用的 Vue 3 前端共存于同一服务、同一端口。

> 本包前端版本 `frontVersion = 1.0.48.102`，后端 `appVersion = 1.0.48`。

## 访问方式

- 现代浏览器（手机 / PC）：`http://<NAS>:7777/`，使用 XRead Vue 3 前端，调后端 `/reader3/*` API。
- Kindle 老浏览器：`http://<NAS>:7777/xread/`，使用 XRead-kindle 静态页面，加载后以**同源**方式访问 `/reader3/*` API。

> 末尾的 `/` 建议保留；若访问 `/xread`（无斜杠），二进制会 301 重定向到 `/xread/`。

## 为什么这样部署

- 后端 `router.rs` 用 `ServeDir::new(web_root)` 作静态兜底，把 `web_root`（即 `app/web/dist`）
  **下任意子目录 / 文件**以 `/xread/...` 对外提供，并自动附加 `index.html`。
- XRead-kindle 的 `index.html` 全部使用**相对路径**（`css/`、`js/`、`img/`、`fonts/`），挂在 `/xread/` 下
  自动解析为 `/xread/css/...` 等，无需任何路由改动。
- 其 `js/config.js` 中 `address` 留空，运行时由 `pageOrigin()` 用
  `window.location.protocol + "//" + window.location.host` 拼出「加载页面的源」。
  **刻意不用 `window.location.origin`**——老 Kindle 的 WebKit 无该属性，误用会让 API 地址变成
  `undefined/reader3/...` 而登录失败。因此页面在 `7777` 还是 `7778` 部署，API 都自动指向
  **同一来源**的 `/reader3/...`，**免 CORS**、无需改配置。
  如需指向独立后端，把 `address` 填成完整地址（如 `http://192.168.31.51:7777`）即可。
- **登录页「地址」输入框会自动填入飞牛本机地址**（当前访问的源），Kindle 无需手输 IP:端口，直接填用户名/密码即可；手动清空或修改仍可指向独立后端。
- 运行时配置由 `window.__XREAD_CONFIG__` 注入，含 `secure`（鉴权）、`appVersion`、`frontVersion`、`debug`
  等字段；`cmd/main` 启动时按安装向导配置替换占位值。

## 构建流程

`build.sh` 在打包时把 xread-kindle 源码复制到 Web 根的 /xread 子路径（运行时唯一挂载点）：

```bash
# 挂到 Web 根的 /xread 子路径（运行时由后端静态兜底路由提供）
cp -a "$KINDLE_SRC/." "$STAGE/app/web/dist/xread/"
```

不再额外复制 `app/kindle/`：那份是构建中间态，启动脚本与后端都不引用，完整源码仍在 xread-kindle 仓库。

因此源码基线中的任何改动（HTML / JS / CSS / 图片 / 字体 / 文档）都会随 `.fpk` 进入安装包，
最终部署到运行时的 `WEB_ROOT/xread/`。

## 目录（打包入包后）

```
app/web/dist/xread/        (运行时 /xread 路径)
├── index.html             入口（相对路径引用资源，含 __XREAD_CONFIG__ 运行配置）
├── js/
│   ├── config.js          address 留空 = 同源自适应
│   └── kindle.js          阅读器主程序（已适配 /reader3 API，ES5）
├── css/
│   ├── kindle.css         Kindle 主样式（CRLF，21px 字体框等老内核适配）
│   └── other.css          手机 / PC 适配样式
├── img/                   界面图片 / 图标
├── fonts/                 中文 woff 字体（阅读渲染依赖）
└── API文档.md             接口清单
```

> 静态前端源码即产物，不需要编译；`build.sh` 直接复制，并剔除源仓库的 `.git`、`out/` 等无关文件。

## 老浏览器兼容要点

- **ES5 JavaScript**：不用 ES6 语法（let/const/箭头函数等），兼容 Kindle WebKit 534。
- **换行符**：HTML = LF；CSS / JS = CRLF。
- **布局**：块级 / float / 固定 px，避开 flex gap、clamp 等老内核不支持的特性。
- **表单控件**：`<select>` 在老内核对 `line-height` / `padding` / `box-sizing` 解析异常，字体框用
  `-webkit-appearance:none` + 背景箭头 + 固定宽度专门校准。
- **缩放**：viewport 只保留老内核必认的键，避免聚焦输入框时整页放大；静态资源带 `?v=<版本>` 参数规避强缓存。

## 更新 Kindle 前端

1. 在源码基线 [bingkuomiao/xread-kindle](https://github.com/bingkuomiao/xread-kindle) 中修改并推送。
2. 本工程执行 `./build.sh --pull`（或确认本地 `xread-kindle` 已是最新），重新打包。
3. 重新打开 `http://<NAS>:7777/xread/` 即可生效（前端强制禁缓存）。
