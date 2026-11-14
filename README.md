# sing-box Lite (OpenWrt 25.12+)

轻量、裸核的 sing-box LuCI 管理面板：把机场订阅和自建 VPS 节点转换成 sing-box 配置，支持可配置规则集、国家/自定义出口组、定时刷新和核心更新。不接管防火墙，不生成 TUN/TPROXY。

## 功能

- **多机场 + 自建节点**：多个订阅 URL、手动分享链接/outbound JSON，统一节点池。
- **订阅转换**：base64/URI 列表、sing-box JSON、Clash YAML（需要 `yq`）。
- **可配置规则集**：内置国内/AI/流媒体/社交/开发规则集；支持内联域名/IP、远程 `.srs` URL、本地 `.srs` 路径。
- **可配置出口组**：内置直连/自动/默认/美国/日本/香港/其他国/原生组；支持自定义 `selector`/`urltest` 组。
- **分流规则**：规则集 → 出口组的可排序列表；自定义规则优先于内置规则。
- **裸核运行**：`mixed` 入站，只运行 sing-box 核心；不修改 `firewall`/`network`/`dhcp`。
- **定时刷新**：cron 拉取订阅 → 重建 → `sing-box check` → 可选自动重启；失败保留旧配置。
- **核心管理**：最低 sing-box 1.14.4；GitHub 最新稳定版下载、校验、原子替换、失败回滚。
- **版本管理**：设置页可查看核心与插件当前版本，从 GitHub Release 列表选择版本，一键更新核心或插件（插件走 apk 覆盖安装）。
- **实时面板**：默认托管官方 [sing-box dashboard](https://github.com/SagerNet/sing-box-dashboard)（`clash_api.external_ui`，随包内嵌入口），也可切换为内置 LuCI 面板（流量、连接、代理组切换与测速）；Clash API 默认监听 `0.0.0.0:9090` 并带随机密钥。
- **LuCI 页面**：概览、订阅、节点、规则集/分流、出口组、设置、日志。

## 环境要求

- OpenWrt 25.12+（apk 包管理；24.10 仅为 best-effort）。
- 架构：x86_64、aarch64、armv7/armv6/armv5、mips/mipsel、mips64/mips64el、riscv64、loongarch64（取决于 sing-box 官方资产）。
- 至少约 120MB 可用空间（完整 sing-box 1.14.4 二进制约 88MB，压缩包约 32MB）。
- 大陆网络建议准备 GitHub 镜像（设置页可填 `https://ghfast.top/` 等）。

## 安装

从 Release 下载 `.apk` 后：

```sh
apk add --allow-untrusted ./singbox-lite-*.apk ./luci-app-singbox-lite-*.apk
```

刷新 LuCI 页面，进入 **服务 → sing-box Lite**。首次使用：

1. 在“概览”点“更新核心”，或先手动安装 sing-box ≥1.14.4。
2. 在“订阅”添加机场订阅，或在“节点”添加自建链接。
3. “概览 → 保存并检查配置”，再点“启动”。
4. 在“规则集/分流”“出口组”按自己的使用习惯调整目标。

> 本插件不依赖 OpenWrt 软件源里的 `sing-box` 包（25.12 源为 1.13.21，低于 1.14.4 最低要求）。核心默认下载到 `/usr/libexec/singbox-lite/sing-box`。

## 配置与数据

| 路径 | 说明 |
|---|---|
| `/etc/config/singbox-lite` | UCI：服务、面板、订阅、节点、规则集、出口组、覆盖设置 |
| `/etc/singbox-lite/config.json` | 生成的 sing-box 配置（0600） |
| `/etc/singbox-lite/config.json.bak` | 上一份可用配置 |
| `/etc/singbox-lite/subs/` | 订阅原始内容 |
| `/etc/singbox-lite/meta/` | 订阅解析结果、流量/到期 |
| `/etc/singbox-lite/rulesets/` | 用户更新/自定义规则集 |
| `/etc/singbox-lite/ui/` | 官方 dashboard 静态文件（`external_ui`） |
| `/usr/share/singbox-lite/rulesets/` | 内置规则集 |
| `/usr/libexec/singbox-lite/sing-box` | 托管核心 |

## 分流与出口模型

- **分流**决定“这是什么流量”：自定义 > 国内 AI > 国内 > 国外 AI > 流媒体 > 社交 > 开发 > 默认。
- **出口**决定“从哪出去”：直连、自动组、默认组、美国/日本/香港/其他国、原生组、自定义组。
- 国内和国内 AI 固定直连；其他类别默认走默认组，可在“规则集/分流”改为国家组/自动组/原生组/自定义组。
- 原生组按节点名关键词（原生/native/家宽…）自动收集，也可手动勾选；**不参与自动选择**，需要时手动把某类流量的出口切到原生组。
- 国家组按节点名关键词自动归类（美国/US/洛杉矶…、日本/JP/东京…、香港/HK…），每个节点可在“节点”页覆盖。

## 面板

面板有两种形态，在「设置 → 面板 → 面板类型」切换：

### 官方 sing-box dashboard（默认）

[SagerNet/sing-box-dashboard](https://github.com/SagerNet/sing-box-dashboard) 的构建产物，由 sing-box 通过 `clash_api.external_ui` 在 `http://<路由器>:9090/ui/` 直接托管（同源，无 CORS 问题）。

1. 设置页点「下载面板文件」，从 GitHub（可用镜像）拉取 `gh-pages` 归档并解包到 `/etc/singbox-lite/ui`；
2. 保存配置并重启服务，生成器会写入 `experimental.clash_api.external_ui`；
3. 打开「面板」页即可内嵌使用；首次进入时在面板里填一次 API 地址与密钥（密钥在面板页显示，可一键复制），浏览器会记住。

注意：官方面板需要 Clash API 监听 `0.0.0.0`（默认）或局域网地址，仅监听 `127.0.0.1` 时只能从路由器本机访问，生成配置会给出警告。

### 内置 LuCI 面板

不依赖外部资源，由插件后端代理 Clash API：

- 状态：核心版本、运行模式、累计上传/下载、活动连接数；
- 代理组：`selector`/`fallback` 组可直接切换节点，所有组都能对成员做延迟测速；
- 连接列表：最近 30 条连接的主机、命中规则、链路、网络与流量，可单独关闭。

### 通用说明

Clash API 由 `config panel 'panel'` 控制：`enabled`、`listen`、`port`、`secret`、`dashboard`。密钥由 uci-defaults 首次安装时随机生成，也可在设置页重新生成。

连 metacubexd / yacd 等其他面板时，把 `listen` 设为 `0.0.0.0`、在「设置 → 面板」保存后重启服务，并自行在防火墙放行该端口——这属于本插件「不改防火墙」之外的操作用户自理。

## 构建

需要 OpenWrt SDK 25.12（x86_64 或对应架构）。把两个包目录放入 SDK 的 `package/` 下，安装 feeds 后：

```sh
make defconfig
make package/singbox-lite/compile V=s
make package/luci-app-singbox-lite/compile V=s
```

或使用仓库的 GitHub Actions（`.github/workflows/build.yml`），输出 `.apk`。

## 测试

```sh
# 主机需要 ucode；见 tests/README.md
mkdir -p /tmp/sbxmods
for m in common config links nodes rulesets subs generator core releases plugin panel; do
  ln -sf "$PWD/singbox-lite/files/usr/share/singbox-lite/ucode/$m.uc" "/tmp/sbxmods/sbx_$m.uc"
done
ucode -L /tmp/sbxmods tests/run.uc
```

`tests/run.uc` 覆盖链接解析、订阅格式、节点分类、规则集/出口组生成。`tests/check-config.sh` 和 `tests/matrix.sh` 会调用下载的 sing-box 1.14.4 执行 `sing-box check`。

## 许可证与规则集

项目代码：GPL-3.0-or-later。

内置 `sing-geosite` / `sing-geoip` 规则集来自 [SagerNet/sing-geosite](https://github.com/SagerNet/sing-geosite) 与 [SagerNet/sing-geoip](https://github.com/SagerNet/sing-geoip)，遵循 GPL-3.0；许可证文件见 `singbox-lite/files/usr/share/singbox-lite/rulesets/LICENSE.*`。

## 限制

- 单份生成配置；不做 profile/多配置切换。
- 不实现 TUN/TPROXY/Redirect、DNS 劫持、FakeIP、访问控制。
- 插件自更新依赖 GitHub Release 中 `singbox-lite-<arch>-openwrt-25.12.tar.gz`，仅覆盖 x86_64 与 aarch64_cortex-a53 两种构建。
- Clash YAML 转换依赖 `yq`，不是硬依赖。
- 规则集随包提供，更新内置规则集需要访问 GitHub 或镜像。

## 免责声明

本项目仅用于合法的网络访问与设备管理。请遵守当地法律法规与网络服务条款。
