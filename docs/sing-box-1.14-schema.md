# sing-box 1.14.4 JSON 配置 Schema 参考

本文以仓库内 `dist/sing-box-1.14.4-linux-amd64-musl` 执行 `sing-box schema` 生成的 JSON Schema 为准，字段含义参考 sing-box 官方中文文档。它回答三个问题：**有哪些顶层块、每个 key 做什么、可以取什么值**。

生成/核对命令：

```json
./dist/sing-box-1.14.4-linux-amd64-musl schema -o schema.json
./dist/sing-box-1.14.4-linux-amd64-musl check -c config.json   # 只校验，不启动
```

> 说明：官方文档站当前对应 1.15.x，本文只保留 1.14.4 Schema 中真实存在的字段；1.15 新增的 `tailcat`、MASQUE endpoint、TUN 的 `multi_queue` 等不在本文范围内。Schema 为 JSON Schema Draft 2020-12，随二进制构建的编译标签变化（如是否带 `with_quic`）。

## 0. 怎么读这份文档

- **顶层块**（§1）决定配置的骨架，除 `$schema` 外都可以省略。

- **type/action 是判别式**：`inbounds[]`、`outbounds[]`、`dns.servers[]`、`endpoints[]`、`services[]` 都是 `oneOf`，先有 `type`，才有该类型对应的字段；规则则用 `action` 区分动作。

- **tag 是引用键**：`route.final`、`selector.outbounds`、`route.rules[].outbound`、`dns.rules[].server`、`rule_set`、`domain_resolver` 等都按 tag 引用对象，必须唯一。

- **表头**：字段名加粗表示必填；「取值 / 默认」列给出枚举、范围或对象入口；说明列末尾的 `（1.14+）` 表示该字段从该版本才可用。

- `sing-box` 解码时启用 `DisallowUnknownFields`：**拼错或写入已移除的字段会直接报错**，不是忽略。

## 1. 顶层结构

一个最小配置可以只有 `log` 和 `outbounds`；实际使用通常是：

```json
{
  "$schema": "https://sing-box.sagernet.org/schema.json",
  "log": {},
  "dns": {},
  "inbounds": [],
  "outbounds": [],
  "route": {},
  "experimental": {}
}
```

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `$schema` | string |  | JSON Schema 的 URI，供编辑器做补全和校验；可写官方地址或本地文件路径。 |
| `log` | object |  | 日志：级别、输出目标、时间戳。 |
| `dns` | object |  | DNS：服务器、规则、缓存、最终策略。 |
| `ntp` | object |  | NTP 时间同步，默认关闭。 |
| `certificate` | object |  | 全局根证书库：信任哪些 CA、额外证书/目录。 |
| `certificate_providers` | array<object> |  | 证书提供者：ACME、Cloudflare Origin CA、Tailscale。 |
| `http_clients` | array<object> |  | 可复用的 HTTP 客户端（供远程规则集、ACME、订阅等引用）。 |
| `network_namespaces` | array<object> |  | Linux 网络命名空间定义，供 `netns` 字段引用。 |
| `endpoints` | array<object> |  | 接口型组件：WireGuard、Tailscale、OpenVPN、OpenConnect。 |
| `inbounds` | array<object> |  | 入站监听器列表：端口、TUN、透明代理等。 |
| `outbounds` | array<object> |  | 出站列表：节点、代理协议、选择器、直连/拒绝等。 |
| `route` | object |  | 路由：规则、规则集、默认出站、全局拨号默认值。 |
| `services` | array<object> |  | 内置服务：API、DERP、resolved、USB/IP 等。 |
| `experimental` | object |  | 实验性功能：缓存文件、Clash API、V2Ray API、调试。 |

`certificate`、`log`、`dns`、`route`、`experimental` 是单对象；`certificate_providers`、`http_clients`、`network_namespaces`、`endpoints`、`inbounds`、`outbounds`、`services` 是数组。

## 2. 通用规则与取值

### 2.1 单值与数组

文档中标注「当内容只有一项时可以忽略数组」的字段（如 `address`、`domain_suffix`、`certificate`）在 Schema 里通常是 `string | array<string>`，两种写法都合法。

### 2.2 时长

所有 `Duration` 字段使用 Go 时长字符串：`ns`/`us`/`ms`/`s`/`m`/`h`/`d`，可组合（`1h30m`），也接受纯数字（纳秒）。

### 2.3 域名策略与网络策略

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `domain_strategy` / `strategy` | 枚举 | `as_is` / `prefer_ipv4` / `prefer_ipv6` / `ipv4_only` / `ipv6_only` | 决定域名解析时优先/只使用哪一族 IP；空字符串表示跟随默认。 |
| `network_strategy` | 枚举 | `default` / `fallback` / `hybrid` | 多网卡/多网络类型下的拨号策略：默认、失败回退、混合。 |
| `network_type` | 枚举/数组 | `cellular` / `ethernet` / `wifi` / `other` | 限定拨号使用的网络类型；`fallback_network_type` 是回退集合。 |

### 2.4 tag 与引用

所有带 `tag` 的对象（入站、出站、DNS 服务器、endpoint、规则集、证书提供者、HTTP 客户端、网络命名空间）共享一个命名空间规则：同一类对象内 tag 必须唯一；引用不存在的 tag 会在 `check` 阶段报错。

## 3. 全局设置

### 3.1 `log` — 日志

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `disabled` | boolean | `true` / `false` | 禁用日志，启动后不输出日志。 |
| `level` | string | `trace` / `debug` / `info` / `warn` / `warning` / `error` / `fatal` / `panic` | 日志等级，可选值：`trace` `debug` `info` `warn` `error` `fatal` `panic`。 |
| `output` | string | — | 输出文件路径，启动后将不输出到控制台。 |
| `timestamp` | boolean | `true` / `false` | 添加时间到每行。 |

`level` 可选 `trace`/`debug`/`info`/`warn`/`warning`/`error`/`fatal`/`panic`；`output` 为文件路径，空表示 stderr；`timestamp` 控制每行是否带时间。

### 3.2 `dns` — DNS 总表

`dns.servers[]` 与 `dns.rules[]` 的细节在 §4。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `final` | string | — | 默认 DNS 服务器的标签。 默认使用第一个服务器。 （按 tag 引用） |
| `reverse_mapping` | boolean | `true` / `false` | 在响应 DNS 查询后存储 IP 地址的反向映射以为路由目的提供域名。 由于此过程依赖于应用程序在发出请求之前解析域名的行为，因此在 macOS 等 DNS 由系统代理和缓存的环境中可能会出现问题。 |
| `strategy` | 枚举 | `as_is` / `prefer_ipv4` / `prefer_ipv6` / `ipv4_only` / `ipv6_only` | 默认解析域名策略。 可选值: `prefer_ipv4` `prefer_ipv6` `ipv4_only` `ipv6_only`。 |
| `timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 每次 DNS 查询的默认超时时间。 默认使用 `10s`。 可被 `rules.[].timeout`（DNS 规则动作）或 `domain_resolver.timeout` 覆盖。（1.14.0+） |
| `disable_cache` | boolean | `true` / `false` | 禁用 DNS 缓存。 与 `optimistic` 冲突。 |
| `disable_expire` | boolean | `true` / `false` | 禁用 DNS 缓存过期。 与 `optimistic` 冲突。 |
| `cache_capacity` | integer（0–4294967295） | 整数 | LRU 缓存容量。 小于 1024 的值将被忽略。（1.11.0+） |
| `optimistic` | boolean 或 object | `true` / `false`，或 `{ enabled, timeout }` | 启用乐观 DNS 缓存。当缓存的 DNS 条目已过期但仍在超时窗口内时， 立即返回过期的响应，同时在后台触发刷新。 与 `disable_cache` 和 `disable_expire` 冲突。 接受布尔值或对象。当设置为 `true` 时，使用默认超时 `3d`。 enabled 启用乐观 DNS 缓存。 timeout 过期缓存条目可被乐观提供的最长时间。 默认使用 `3d`。（1.14.0+） |
| `client_subnet` | string | — | 默认情况下，将带有指定 IP 前缀的 `edns0-subnet` OPT 附加记录附加到每个查询。 如果值是 IP 地址而不是前缀，则会自动附加 `/32` 或 `/128`。 可以被 `servers.[].client_subnet` 或 `rules.[].client_subnet` 覆盖。（1.9.0+） |

`strategy` 是全局域名策略；`final` 是未命中规则时使用的 DNS 服务器 tag；`reverse_mapping` 让 FakeIP 反查的域名也写回映射；`optimistic` 可开启乐观缓存（布尔或对象）；`client_subnet` 是默认 EDNS Client Subnet。

### 3.3 `ntp` — 时间同步

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `enabled` | boolean | `true` / `false` | 启用 NTP 服务。 |
| `interval` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 时间同步间隔。 默认使用 30 分钟。 |
| `write_to_system` | boolean | `true` / `false` | 把 NTP 校时结果写回系统时钟。 |
| **`server`** | string | — | NTP 服务器地址。 |
| `server_port` | integer（0–65535） | 整数 | NTP 服务器端口。 默认使用 123。 |
| `detour` | string | — | 上游出站的标签。 启用时，其他拨号字段将被忽略。 （按 tag 引用） |
| `bind_interface` | string | — | 要绑定到的网络接口。 |
| `inet4_bind_address` | string | — | 要绑定的 IPv4 地址。 |
| `inet6_bind_address` | string | — | 要绑定的 IPv6 地址。 |
| `bind_address_no_port` | boolean | `true` / `false` | 绑定到源地址时不保留端口。 这允许在完整的四元组（源 IP、源端口、目标 IP、目标端口）保持唯一的情况下，为多个连接复用同一源端口。（1.13.0+） |
| `protect_path` | string | — | 仅 Android：把底层套接字绑定到指定 VPN 路径（VpnService.protect）。 |
| `routing_mark` | integer（0–4294967295） 或 string | 整数，或 `0x...` 十六进制字符串 | 设置 netfilter 路由标记。 支持数字 (如 `1234`) 和十六进制字符串 (如 `"0x1234"`)。 |
| `reuse_addr` | boolean | `true` / `false` | 重用监听地址。 |
| `netns` | string | — | 设置网络命名空间，名称或路径。 应避免引用 `unshare` 类型的网络命名空间。（1.14.0+） （按 tag 引用） |
| `connect_timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 连接超时，采用 golang 的 Duration 格式。 持续时间字符串是一个可能有符号的序列十进制数，每个都有可选的分数和单位后缀， 例如 "300ms"、"-1.5h" 或 "2h45m"。 有效时间单位为 "ns"、"us"（或 "µs"）、"ms"、"s"、"m"、"h"。 |
| `tcp_fast_open` | boolean | `true` / `false` | 启用 TCP Fast Open。 |
| `tcp_multi_path` | boolean | `true` / `false` | 需要 Go 1.21。 启用 TCP Multi Path。 |
| `disable_tcp_keep_alive` | boolean | `true` / `false` | 禁用 TCP keep alive。（1.13.0+） |
| `tcp_keep_alive` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 默认值从 `10m` 更改为 `5m`。 TCP keep alive 初始周期。 默认使用 `5m`。（1.13.0+） |
| `tcp_keep_alive_interval` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | TCP keep alive 间隔。 默认使用 `75s`。（1.13.0+） |
| `udp_fragment` | boolean | `true` / `false` | 启用 UDP 分段。 |
| `domain_resolver` | string/object | DNS 服务器 tag，或内联 `{ server, ... }` | 用于解析服务器域名的 DNS 服务器标签，或内联解析器对象（见 §5.2）。 |
| `network_strategy` | string | `default` / `fallback` / `hybrid` | 仅在 Android 与 iOS 平台图形客户端中支持，并且需要 `route.auto_detect_interface`。 用于选择网络接口的策略。 可用值：`default`（默认值）：按顺序连接默认网络或 `network_type` 中指定的网络。、`hybrid`：同时连接所有网络或 `network_type` 中指定的网络。、`fallback`：同时连接默认网络或 `network_type` 中指定的首选网络，当…（1.11.0+） |
| `network_type` | 枚举 或 array<枚举> | `cellular` / `ethernet` / `wifi` / `other`（可数组） | 仅在 Android 与 iOS 平台图形客户端中支持，并且需要 `route.auto_detect_interface`。 当使用 `default` 或 `hybrid` 网络策略时要使用的网络类型，或当使用 `fallback` 网络策略时要使用的首选网络类型。 可用值：`wifi`, `cellular`, `ethernet`, `other`。 默认使用设备默认网络。（1.11.0+） |
| `fallback_network_type` | 枚举 或 array<枚举> | `cellular` / `ethernet` / `wifi` / `other`（可数组） | 仅在 Android 与 iOS 平台图形客户端中支持，并且需要 `route.auto_detect_interface`。 当使用 `fallback` 网络策略时，在首选网络不可用或超时的情况下要使用的回退网络类型。 默认使用除首选网络外的所有其他网络。（1.11.0+） |
| `fallback_delay` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 在生成 RFC 6555 快速回退连接之前等待的时间长度。 对于 `domain_strategy`，是在假设之前等待 IPv6 成功的时间量如果设置了 "prefer_ipv4"，则 IPv6 配置错误并回退到 IPv4。 对于 `network_strategy`，对于 `network_strategy`，是在回退到其他接口之前等待连接成功的时间。 仅当 `domain_strategy` 或 `network_strateg… |

`enabled` 默认 `false`；`interval` 默认 `30m`；`write_to_system` 把校时结果写回系统时钟；其余为拨号字段（NTP 请求走哪个出站/接口）。

### 3.4 `certificate` — 根证书库

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `store` | string | `system` / `mozilla` / `chrome` / `none` | 默认受信任 CA 列表：`system`（系统，默认）/ `mozilla` / `chrome` / `none`。 |
| `certificate` | string 或 array<string> | — | 要信任的证书行数组，PEM 格式。 |
| `certificate_path` | string 或 array<string> | — | 文件修改时将自动重新加载。 要信任的证书路径，PEM 格式。 |
| `certificate_directory_path` | string 或 array<string> | — | 文件修改时将自动重新加载。 搜索要信任的证书的目录路径，PEM 格式。 |

### 3.5 `certificate_providers` — 证书提供者

用于自动签发/加载证书，供各处的 `tls.certificate_provider` 按 tag 引用。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `acme` | object | 见下 | ACME 自动证书（Let’s Encrypt 等），支持 HTTP-01、TLS-ALPN-01、DNS-01。 |
| `cloudflare-origin-ca` | object | 见下 | Cloudflare Origin CA 证书。 |
| `tailscale` | object | 见下 | 使用 Tailscale endpoint 的证书。 |

#### `acme`

ACME 自动证书（Let’s Encrypt 等），支持 HTTP-01、TLS-ALPN-01、DNS-01。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `tag` | string | — | 证书提供者的标签。 |
| **`domain`** | string 或 array<string> | — | 域名列表。 |
| `data_directory` | string | — | ACME 数据存储目录。 如果为空则使用 `$XDG_DATA_HOME/certmagic\|$HOME/.local/share/certmagic`。 |
| `default_server_name` | string | — | 如果 ClientHello 的 ServerName 字段为空，则选择证书时要使用的服务器名称。 |
| `email` | string | — | 创建或选择现有 ACME 服务器帐户时使用的电子邮件地址。 |
| `provider` | string | — | 要使用的 ACME CA 提供商。 当 `provider` 为 `zerossl` 时，如果设置了 `email` 且未设置 `external_account`， sing-box 会自动向 ZeroSSL 请求 EAB 凭据。 当 `provider` 为 `zerossl` 时，必须至少设置 `external_account`、`email` 或 `account_key` 之一。 |
| `account_key` | string | — | 现有 ACME 帐户的 PEM 编码私钥。（1.14.0+） |
| `disable_http_challenge` | boolean | `true` / `false` | 禁用所有 HTTP 质询。 |
| `disable_tls_alpn_challenge` | boolean | `true` / `false` | 禁用所有 TLS-ALPN 质询。 |
| `alternative_http_port` | integer（0–65535） | 整数 | 用于 ACME HTTP 质询的备用端口；如果非空，将使用此端口而不是 80 来启动 HTTP 质询的侦听器。 |
| `alternative_tls_port` | integer（0–65535） | 整数 | 用于 ACME TLS-ALPN 质询的备用端口； 系统必须将 443 转发到此端口以使质询成功。 |
| `external_account` | object | 对象 | EAB（外部帐户绑定）包含将 ACME 帐户绑定或映射到 CA 已知的其他帐户所需的信息。 外部帐户绑定用于将 ACME 帐户与非 ACME 系统中的现有帐户相关联，例如 CA 客户数据库。 为了启用 ACME 帐户绑定，运行 ACME 服务器的 CA 需要使用 ACME 之外的某种机制向 ACME 客户端提供 MAC 密钥和密钥标识符。§7.3.4 |
| `dns01_challenge` | object | 对象 | ACME DNS01 质询字段。如果配置，将禁用其他质询方法。 参阅 DNS01 质询字段。 |
| `key_type` | string | `ed25519` / `p256` / `p384` / `rsa2048` / `rsa4096` | 为新证书生成的私钥类型。（1.14.0+） |
| `profile` | string | — | 用于证书签发的 ACME profile。 当为空且 `provider` 为 Let's Encrypt 时，如果任意域名为 IP 地址，将自动使用 `shortlived`。（1.14.0+） |
| `http_client` | object | HTTP 客户端 tag，或内联对象 | 用于所有提供者 HTTP 请求的 HTTP 客户端。 参阅 HTTP 客户端字段 了解详情。（1.14.0+） |

#### `cloudflare-origin-ca`

Cloudflare Origin CA 证书。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `tag` | string | — | 证书提供者的标签。 |
| **`domain`** | string 或 array<string> | — | 要写入证书的域名或通配符域名列表。 |
| `data_directory` | string | — | 保存签发证书、私钥和元数据的根目录。 如果为空，sing-box 会使用与 ACME 证书提供者相同的默认数据目录： `$XDG_DATA_HOME/certmagic` 或 `$HOME/.local/share/certmagic`。 |
| `api_token` | string | — | 用于创建证书的 Cloudflare API Token。 可在 Cloudflare Dashboard > My Profile > API Tokens 获取或创建。 需要 `Zone / SSL and Certificates / Edit` 权限。 与 `origin_ca_key` 冲突。 |
| `origin_ca_key` | string | — | Cloudflare Origin CA Key。 可在 Cloudflare Dashboard > My Profile > API Tokens > API Keys > Origin CA Key 获取。 与 `api_token` 冲突。 |
| `request_type` | string | `origin-rsa` / `origin-ecc` | 向 Cloudflare 请求的签名类型。 如果为空，使用 `origin-rsa`。 |
| `requested_validity` | integer | `0` / `7` / `30` / `90` / `365` / `730` / `1095` / `5475` | 请求的证书有效期，单位为天。 可用值：`7`、`30`、`90`、`365`、`730`、`1095`、`5475`。 如果为空，使用 `5475` 天（15 年）。 |
| `http_client` | object | HTTP 客户端 tag，或内联对象 | 用于所有提供者 HTTP 请求的 HTTP 客户端。 参阅 HTTP 客户端字段 了解详情。 |

#### `tailscale`

使用 Tailscale endpoint 的证书。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `tag` | string | — | 证书提供者的标签。 |
| **`endpoint`** | string | — | 要复用的 Tailscale 端点 的标签。 必须在 Tailscale 管理控制台中启用 MagicDNS 和 HTTPS。 |

### 3.6 `http_clients` — 可复用 HTTP 客户端

`http_clients[]` 定义带拨号/TLS/HTTP2/QUIC 设置的 HTTP 客户端；远程规则集、ACME 等用 `http_client` 字段按 tag 引用。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `tag` | string | — | 唯一标签；远程规则集/ACME 用 `http_client` 引用。 |
| `engine` | string | `go` / `apple` | 要使用的 HTTP 引擎。 可用值：`go`（默认）、`apple` `apple` 使用 NSURLSession，仅在 Apple 平台可用。 仅供实验用途：不应在 iOS 和 tvOS 的热路径中使用。 支持的字段：`headers`、`tls.server_name`（必须与请求主机匹配）、`tls.insecure`、`tls.min_version` / `tls.max_version`、`tls.certificat… |
| `version` | integer | `0` / `1` / `2` / `3` | HTTP 版本。 可用值：`1`、`2`、`3`。 默认使用 `2`。 当为 `3` 时，HTTP2 字段 替换为 QUIC 字段。 |
| `disable_version_fallback` | boolean | `true` / `false` | 禁用自动回退到更低的 HTTP 版本。 |
| `headers` | object | 键值对（值可为字符串或数组） | 自定义 HTTP 标头。 `Host` 标头用作请求主机。 |
| `tls` | object | 对象，见 §5.3 | TLS 配置对象（见 §5.3）。 |
| `detour` | string | — | 上游出站的标签。 启用时，其他拨号字段将被忽略。 （按 tag 引用） |
| `bind_interface` | string | — | 要绑定到的网络接口。 |
| `inet4_bind_address` | string | — | 要绑定的 IPv4 地址。 |
| `inet6_bind_address` | string | — | 要绑定的 IPv6 地址。 |
| `bind_address_no_port` | boolean | `true` / `false` | 绑定到源地址时不保留端口。 这允许在完整的四元组（源 IP、源端口、目标 IP、目标端口）保持唯一的情况下，为多个连接复用同一源端口。（1.13.0+） |
| `protect_path` | string | — | 仅 Android：把底层套接字绑定到指定 VPN 路径（VpnService.protect）。 |
| `routing_mark` | integer（0–4294967295） 或 string | 整数，或 `0x...` 十六进制字符串 | 设置 netfilter 路由标记。 支持数字 (如 `1234`) 和十六进制字符串 (如 `"0x1234"`)。 |
| `reuse_addr` | boolean | `true` / `false` | 重用监听地址。 |
| `netns` | string | — | 设置网络命名空间，名称或路径。 应避免引用 `unshare` 类型的网络命名空间。（1.14.0+） （按 tag 引用） |
| `connect_timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 连接超时，采用 golang 的 Duration 格式。 持续时间字符串是一个可能有符号的序列十进制数，每个都有可选的分数和单位后缀， 例如 "300ms"、"-1.5h" 或 "2h45m"。 有效时间单位为 "ns"、"us"（或 "µs"）、"ms"、"s"、"m"、"h"。 |
| `tcp_fast_open` | boolean | `true` / `false` | 启用 TCP Fast Open。 |
| `tcp_multi_path` | boolean | `true` / `false` | 需要 Go 1.21。 启用 TCP Multi Path。 |
| `disable_tcp_keep_alive` | boolean | `true` / `false` | 禁用 TCP keep alive。（1.13.0+） |
| `tcp_keep_alive` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 默认值从 `10m` 更改为 `5m`。 TCP keep alive 初始周期。 默认使用 `5m`。（1.13.0+） |
| `tcp_keep_alive_interval` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | TCP keep alive 间隔。 默认使用 `75s`。（1.13.0+） |
| `udp_fragment` | boolean | `true` / `false` | 启用 UDP 分段。 |
| `domain_resolver` | string/object | DNS 服务器 tag，或内联 `{ server, ... }` | 用于解析服务器域名的 DNS 服务器标签，或内联解析器对象（见 §5.2）。 |
| `network_strategy` | string | `default` / `fallback` / `hybrid` | 仅在 Android 与 iOS 平台图形客户端中支持，并且需要 `route.auto_detect_interface`。 用于选择网络接口的策略。 可用值：`default`（默认值）：按顺序连接默认网络或 `network_type` 中指定的网络。、`hybrid`：同时连接所有网络或 `network_type` 中指定的网络。、`fallback`：同时连接默认网络或 `network_type` 中指定的首选网络，当…（1.11.0+） |
| `network_type` | 枚举 或 array<枚举> | `cellular` / `ethernet` / `wifi` / `other`（可数组） | 仅在 Android 与 iOS 平台图形客户端中支持，并且需要 `route.auto_detect_interface`。 当使用 `default` 或 `hybrid` 网络策略时要使用的网络类型，或当使用 `fallback` 网络策略时要使用的首选网络类型。 可用值：`wifi`, `cellular`, `ethernet`, `other`。 默认使用设备默认网络。（1.11.0+） |
| `fallback_network_type` | 枚举 或 array<枚举> | `cellular` / `ethernet` / `wifi` / `other`（可数组） | 仅在 Android 与 iOS 平台图形客户端中支持，并且需要 `route.auto_detect_interface`。 当使用 `fallback` 网络策略时，在首选网络不可用或超时的情况下要使用的回退网络类型。 默认使用除首选网络外的所有其他网络。（1.11.0+） |
| `fallback_delay` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 在生成 RFC 6555 快速回退连接之前等待的时间长度。 对于 `domain_strategy`，是在假设之前等待 IPv6 成功的时间量如果设置了 "prefer_ipv4"，则 IPv6 配置错误并回退到 IPv4。 对于 `network_strategy`，对于 `network_strategy`，是在回退到其他接口之前等待连接成功的时间。 仅当 `domain_strategy` 或 `network_strateg… |
| `idle_timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 空闲连接超时；不同组件含义略有差异（HTTP2 中为 GOAWAY/PING 健康检查）。 |
| `keep_alive_period` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | QUIC 保活周期；默认由协议决定（通常 0/关闭）。 |
| `stream_receive_window` | integer 或 string | 整数或带单位字符串 | QUIC 单条流的接收窗口（字节数或带单位字符串）。 |
| `connection_receive_window` | integer 或 string | 整数或带单位字符串 | QUIC 连接级接收窗口。 |
| `max_concurrent_streams` | integer | 整数 | QUIC 允许的最大并发流数量。 |
| `initial_packet_size` | integer | 整数 | QUIC 初始数据包大小（字节）。 |
| `disable_path_mtu_discovery` | boolean | `true` / `false` | 关闭 QUIC 的路径 MTU 发现。 |

### 3.7 `network_namespaces` — 网络命名空间

仅 Linux。定义后可在监听/拨号字段中用 `netns` 按 tag 引用，使组件运行在独立 netns 中。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `type` | string | `default`（默认）/ `unshare` | `default` 加入已有命名空间；`unshare` 新建命名空间。 |
| `tag` | string |  | 唯一标签，供 `netns` 引用。 |
| `path` | string |  | `default` 类型：已有命名空间的路径。 |
| `pid_file` | string |  | `unshare` 类型：写入新命名空间 PID 的文件。 |

## 4. DNS

### 4.1 服务器类型

| type | 作用 |
|---|---|
| `local` | 使用系统本地解析器（getaddrinfo/系统 stub），可指定优先 Go 解析或邻居发现。 |
| `hosts` | 静态 hosts：按域名直接返回写死的地址，可指向 hosts 文件。 |
| `tcp` | 经典 DNS over TCP。 |
| `udp` | 经典 DNS over UDP。 |
| `tls` | DNS over TLS（DoT）。 |
| `quic` | DNS over QUIC（DoQ）。 |
| `https` | DNS over HTTPS（DoH）。 |
| `h3` | DNS over HTTP/3（DoH3）。 |
| `dhcp` | 从 DHCP 租约/邻居表取得 DNS 服务器，供局域网客户端使用。 |
| `mdns` | 多播 DNS（mDNS，`.local`）。 |
| `fakeip` | FakeIP 地址池：给域名分配假地址，由路由层根据映射反查真实域名。 |
| `tailscale` | 使用 Tailscale endpoint 提供的 DNS。 |
| `openconnect` | 使用 OpenConnect endpoint 下发的 DNS。 |
| `openvpn` | 使用 OpenVPN endpoint 下发的 DNS。 |
| `resolved` | 对接 systemd-resolved（通过 Resolved 服务）。 |

所有服务器都有 `tag`；`local`/`tcp`/`udp`/`tls`/`quic`/`https`/`h3`/`dhcp`/`mdns` 使用拨号字段，可指定 `detour`、`domain_resolver`、绑定接口等；`fakeip`/`hosts`/`resolved`/`tailscale`/`openconnect`/`openvpn` 是特殊实现。

### 4.2 各类型字段

#### `local` — 使用系统本地解析器（getaddrinfo/系统 stub），可指定优先 Go 解析或邻居发现。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `prefer_go` | boolean | `true` / `false` | 启用后，`local` DNS 服务器将尽可能通过拨号自身来解析 DNS。 具体来说，它禁用了在 sing-box 1.13.0 中作为功能添加的以下行为：在 Apple 平台上：尝试在 NetworkExtension 中使用 `getaddrinfo` 解析 A/AAAA 请求。；在 Linux 上：当可用时通过 `systemd-resolvd` 的 DBus 接口进行解析。 作为唯一的例外，它无法禁用以下行为：在 Andro…（1.13.0+） |
| `neighbor_domain` | string 或 array<string> | — | 用于从邻居解析器而非上游回答 A/AAAA 查询的域后缀列表。 每一项必须以 `.` 开头。仅匹配后缀之前的主机名部分不包含点的查询； `.` 匹配任意单标签名称，例如 `nas`。 示例：`[".", ".lan"]`。（1.14.0+） |

#### `hosts` — 静态 hosts：按域名直接返回写死的地址，可指向 hosts 文件。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `path` | string 或 array<string> | 文件路径（部分字段可为数组） | hosts 文件路径列表。 默认使用 `/etc/hosts`。 在 Windows 上默认使用 `C:\Windows\System32\Drivers\etc\hosts`。 示例： |
| `predefined` | object | 域名 → 地址（或地址数组）的映射 | 预定义的 hosts。 示例： |

#### `tcp` — 经典 DNS over TCP。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`server`** | string | — | DNS 服务器的地址。 如果使用域名，还必须设置 `domain_resolver` 来解析 IP 地址。 |
| `server_port` | integer（0–65535） | 整数 | DNS 服务器的端口。 默认使用 `53`。 |

#### `udp` — 经典 DNS over UDP。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`server`** | string | — | DNS 服务器的地址。 如果使用域名，还必须设置 `domain_resolver` 来解析 IP 地址。 |
| `server_port` | integer（0–65535） | 整数 | DNS 服务器的端口。 默认使用 `53`。 |

#### `tls` — DNS over TLS（DoT）。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`server`** | string | — | DNS 服务器的地址。 如果使用域名，还必须设置 `domain_resolver` 来解析 IP 地址。 |
| `server_port` | integer（0–65535） | 整数 | DNS 服务器的端口。 默认使用 `853`。 |
| `tls` | object | 对象，见 §5.3 | TLS 配置，参阅 TLS。 |

#### `quic` — DNS over QUIC（DoQ）。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`server`** | string | — | DNS 服务器的地址。 如果使用域名，还必须设置 `domain_resolver` 来解析 IP 地址。 |
| `server_port` | integer（0–65535） | 整数 | DNS 服务器的端口。 默认使用 `853`。 |
| `tls` | object | 对象，见 §5.3 | TLS 配置，参阅 TLS。 |

#### `https` — DNS over HTTPS（DoH）。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`server`** | string | — | DNS 服务器的地址。 如果使用域名，还必须设置 `domain_resolver` 来解析 IP 地址。 |
| `server_port` | integer（0–65535） | 整数 | DNS 服务器的端口。 默认使用 `443`。 |
| `tls` | object | 对象，见 §5.3 | TLS 配置，参阅 TLS。 |
| `path` | string | 文件路径（部分字段可为数组） | DNS 服务器的路径。 默认使用 `/dns-query`。 |
| `method` | string | — | HTTP 方法；默认 `GET`，部分服务器需要 `POST`。 |
| `headers` | object | 键值对（值可为字符串或数组） | 发送到 DNS 服务器的额外标头。 |

#### `h3` — DNS over HTTP/3（DoH3）。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`server`** | string | — | DNS 服务器的地址。 如果使用域名，还必须设置 `domain_resolver` 来解析 IP 地址。 |
| `server_port` | integer（0–65535） | 整数 | DNS 服务器的端口。 默认使用 `443`。 |
| `tls` | object | 对象，见 §5.3 | TLS 配置，参阅 TLS。 |
| `path` | string | 文件路径（部分字段可为数组） | DNS 服务器的路径。 默认使用 `/dns-query`。 |
| `method` | string | — | HTTP 方法；默认 `GET`，部分服务器需要 `POST`。 |
| `headers` | object | 键值对（值可为字符串或数组） | 发送到 DNS 服务器的额外标头。 |

#### `dhcp` — 从 DHCP 租约/邻居表取得 DNS 服务器，供局域网客户端使用。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `prefer_go` | boolean | `true` / `false` | 优先通过自身拨号器解析，禁用系统 getaddrinfo/systemd-resolved 的特殊路径。 |
| `neighbor_domain` | string 或 array<string> | — | 通过邻居发现解析的域名后缀列表。 |
| `interface` | string | — | 要监听的网络接口名称。 默认使用默认接口。 |

#### `mdns` — 多播 DNS（mDNS，`.local`）。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `prefer_go` | boolean | `true` / `false` | 优先通过自身拨号器解析，禁用系统 getaddrinfo/systemd-resolved 的特殊路径。 |
| `neighbor_domain` | string 或 array<string> | — | 通过邻居发现解析的域名后缀列表。 |
| `interface` | string 或 array<string> | — | 用于发送 mDNS 查询的网络接口名称列表。 留空时，将使用所有处于 up 状态、支持多播且非环回的接口。 |

#### `fakeip` — FakeIP 地址池：给域名分配假地址，由路由层根据映射反查真实域名。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `inet4_range` | string | CIDR，如 `198.18.0.0/15` | FakeIP 的 IPv4 地址范围。 |
| `inet6_range` | string | CIDR，如 `fc00::/18` | FakeIP 的 IPv6 地址范围。 |

#### `tailscale` — 使用 Tailscale endpoint 提供的 DNS。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`endpoint`** | string | — | Tailscale 端点 的标签。 |
| `accept_default_resolvers` | boolean | `true` / `false` | 指示是否除了 MagicDNS 外，还应接受默认 DNS 解析器以进行回退查询。 如果未启用，对于非 Tailscale 域名查询将返回 `NXDOMAIN`。 |
| `accept_search_domain` | boolean | `true` / `false` | 启用后，单标签查询（例如 `my-device`）将依次附加 Tailscale 搜索域进行重试，直到其中一个解析成功。（1.14.0+） |

#### `openconnect` — 使用 OpenConnect endpoint 下发的 DNS。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`endpoint`** | string | — | OpenConnect 端点 的标签。 DNS 查询会通过 OpenConnect 端点发送到 VPN 服务器推送的解析器。 |
| `accept_default_resolvers` | boolean | `true` / `false` | 接受 VPN 服务器推送的通用解析器，用于未匹配的查询。 启用时，仅当服务器要求所有 DNS 通过隧道，或未提供分流 DNS 规则及后缀时，通用解析器才会作为默认解析器。否则，未匹配的查询将返回 `NXDOMAIN`。 |
| `accept_search_domain` | boolean | `true` / `false` | 启用且存在推送的搜索域时，单标签查询（例如 `intranet`）会依次附加各个搜索域进行重试，直到其中一个解析成功。 如果所有搜索域扩展均返回 `NXDOMAIN`，原始未限定名称将按普通默认解析器行为处理。 |

#### `openvpn` — 使用 OpenVPN endpoint 下发的 DNS。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`endpoint`** | string | — | OpenVPN 客户端端点 的标签。 DNS 查询会通过该端点发送到 OpenVPN 服务器推送的解析器。 支持现代 `dns` 选项，以及传统的 `dhcp-option DNS`/`DNS6` 和 `DOMAIN-ROUTE` 选项。不支持 `dnssec yes`。 |
| `accept_default_resolvers` | boolean | `true` / `false` | 对未匹配推送的 `resolve-domains`、`DOMAIN-ROUTE` 或搜索域后缀的查询使用推送解析器。 禁用时，未匹配查询返回 `NXDOMAIN`。 |
| `accept_search_domain` | boolean | `true` / `false` | 启用且存在推送的搜索域时，单标签查询（例如 `intranet`）会依次附加各个搜索域重试，直到其中一个解析成功。 不存在搜索域时，原始单标签查询按普通默认解析器规则处理。 |

#### `resolved` — 对接 systemd-resolved（通过 Resolved 服务）。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`service`** | string | — | Resolved 服务 的标签。 |
| `accept_default_resolvers` | boolean | `true` / `false` | 指示是否除了匹配域名外，还应接受默认 DNS 解析器以进行回退查询。 具体来说，默认 DNS 解析器是设置了 `SetLinkDefaultRoute` 或 `SetLinkDomains ~.` 的 DNS 服务器。 如果未启用，对于不匹配搜索域或匹配域的请求，将返回 `NXDOMAIN`。 |

### 4.3 DNS 规则

`dns.rules[]` 与路由规则结构相似，但匹配的是 DNS 查询；默认动作是 `route`。匹配字段全部可选，多个字段之间是「与」，同一字段的数组是「或」。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `inbound` | string 或 array<string> | — | 入站 标签. |
| `ip_version` | integer | `4` / `6` | sing-box 1.14.0 中的更改 此字段现在也会在 DNS 规则被未指定具体 DNS 服务器的内部域名解析匹配时生效， 例如未设置 `server` 的 `resolve` 路由规则动作。参阅 迁移指南。 在 DNS 规则中设置此字段后，该 DNS 规则在同一 DNS 配置中不能与 旧版地址筛选字段 (DNS 规则)、旧版 DNS 规则动作 `strategy` 选项， 或旧版 `rule_set_ip_cidr_accep… |
| `query_type` | object 或 array<object> | — | sing-box 1.14.0 中的更改 此字段现在也会在 DNS 规则被未指定具体 DNS 服务器的内部域名解析匹配时生效， 例如未设置 `server` 的 `resolve` 路由规则动作。参阅 迁移指南。 在 DNS 规则中设置此字段后，该 DNS 规则在同一 DNS 配置中不能与 旧版地址筛选字段 (DNS 规则)、旧版 DNS 规则动作 `strategy` 选项， 或旧版 `rule_set_ip_cidr_accep… |
| `query_client_subnet` | string 或 array<string> | — | 匹配查询中的 `edns0-subnet` OPT 附加记录（EDNS 客户端子网）。 列出的前缀在不比收到的客户端子网更具体、且包含其地址时匹配。 如果值是 IP 地址而不是前缀，则会自动附加 `/32` 或 `/128`。（1.14.0+） |
| `query_dnssec` | boolean | `true` / `false` | 匹配设置了 DNSSEC OK (`DO`) 位的查询。（1.14.0+） |
| `network` | string 或 array<string> | 可单值或数组：`tcp` / `udp` | `tcp` 或 `udp`。 |
| `auth_user` | string 或 array<string> | — | 认证用户名，参阅入站设置。 |
| `protocol` | string 或 array<string> | 可单值或数组：`tls` / `http` / `quic` / `dns` / `stun` / `bittorrent` / `dtls` / `ssh` / `rdp` / `ntp` | 探测到的协议, 参阅 协议探测。 |
| `domain` | string 或 array<string> | — | 匹配完整域名。 |
| `domain_suffix` | string 或 array<string> | — | 匹配域名后缀。 |
| `domain_keyword` | string 或 array<string> | — | 匹配域名关键字。 |
| `domain_regex` | string 或 array<string> | — | 匹配域名正则表达式。 |
| `source_ip_cidr` | string 或 array<string> | — | 匹配源 IP CIDR。 |
| `source_ip_is_private` | boolean | `true` / `false` | 匹配非公开源 IP。（1.8.0+） |
| `source_port` | integer（0–65535） 或 array<integer（0–65535）> | — | 匹配源端口。 |
| `source_port_range` | string 或 array<string> | — | 匹配源端口范围。 |
| `port` | integer（0–65535） 或 array<integer（0–65535）> | — | 匹配端口。 |
| `port_range` | string 或 array<string> | — | 匹配端口范围。 |
| `process_name` | string 或 array<string> | — | 匹配进程名称。 |
| `process_path` | string 或 array<string> | — | 匹配进程路径。 |
| `process_path_regex` | string 或 array<string> | — | 使用正则表达式匹配进程路径。（1.10.0+） |
| `package_name` | string 或 array<string> | — | 匹配 Android 应用包名。 |
| `package_name_regex` | string 或 array<string> | — | 使用正则表达式匹配 Android 应用包名。（1.14.0+） |
| `user` | string 或 array<string> | — | 匹配用户名。 |
| `user_id` | integer 或 array<integer> | — | 匹配用户 ID。 |
| `clash_mode` | string | — | 匹配 Clash 模式。 |
| `network_type` | 枚举 或 array<枚举> | `cellular` / `ethernet` / `wifi` / `other`（可数组） | 仅在 Android 与 Apple 平台图形客户端中支持。 匹配网络类型。 Available values: `wifi`, `cellular`, `ethernet` and `other`.（1.11.0+） |
| `network_is_expensive` | boolean | `true` / `false` | 仅在 Android 与 Apple 平台图形客户端中支持。 匹配如果网络被视为计费 (在 Android) 或被视为昂贵， 像蜂窝网络或个人热点 (在 Apple 平台)。（1.11.0+） |
| `network_is_constrained` | boolean | `true` / `false` | 仅在 Apple 平台图形客户端中支持。 匹配如果网络在低数据模式下。（1.11.0+） |
| `wifi_ssid` | string 或 array<string> | — | 仅在 Android 与 Apple 平台图形客户端和 Linux 中支持。 匹配 WiFi SSID。 |
| `wifi_bssid` | string 或 array<string> | — | 仅在 Android 与 Apple 平台图形客户端和 Linux 中支持。 匹配 WiFi BSSID。 |
| `interface_address` | object | 对象 | 匹配接口地址。（1.13.0+） |
| `network_interface_address` | object | 对象 | 仅在 Android 与 Apple 平台图形客户端中支持。 匹配网络接口（可用值同 `network_type`）地址。（1.13.0+） |
| `default_interface_address` | string 或 array<string> | — | 匹配默认接口地址。（1.13.0+） |
| `source_mac_address` | string 或 array<string> | — | 匹配源设备 MAC 地址。（1.14.0+） |
| `source_hostname` | string 或 array<string> | — | 匹配源设备从 DHCP 租约获取的主机名。（1.14.0+） |
| `preferred_by` | string 或 array<string> | — | 匹配指定 DNS 服务器的首选域名。（1.14.0+） |
| `rule_set` | string 或 array<string> | — | 匹配规则集。（1.8.0+） |
| `rule_set_ip_cidr_match_source` | boolean | `true` / `false` | 使规则集中的 `ip_cidr` 规则匹配源 IP。（1.10.0+） |
| `match_response` | boolean 或 string | — | 启用响应匹配。启用后，此规则将匹配已评估的响应（由前序 `evaluate` 动作设置），而不仅是匹配原始查询。 可以为 `true` 或 `evaluate` 动作的 `tag`：`true` 匹配最近一条无 `tag` 的 `evaluate` 动作的响应；标签则匹配对应 `evaluate` 动作的响应。 该已评估的响应也可以被后续的 `respond` 动作直接返回；在带 `match_response` 标签的规则中，`r…（1.14.0+） |
| `ip_cidr` | string 或 array<string> | — | 与查询响应匹配 IP CIDR。 作为旧版地址筛选字段已废弃。请改为配合 `match_response` 使用， 参阅迁移指南。（1.9.0+） |
| `ip_is_private` | boolean | `true` / `false` | 与查询响应匹配非公开 IP。 作为旧版地址筛选字段已废弃。请改为配合 `match_response` 使用， 参阅迁移指南。（1.9.0+） |
| `ip_accept_any` | boolean | `true` / `false` | 当 DNS 查询响应包含至少一个地址时匹配。（1.12.0+） |
| `response_rcode` | object | 对象 | 匹配 DNS 响应码。 接受的值与 predefined 动作 rcode 中相同。 |
| `response_answer` | string 或 array<string> | — | 匹配 DNS 应答记录。 记录格式与 predefined 动作 answer 中相同。 |
| `response_ns` | string 或 array<string> | — | 匹配 DNS 名称服务器记录。 记录格式与 predefined 动作 ns 中相同。 |
| `response_extra` | string 或 array<string> | — | 匹配 DNS 额外记录。 记录格式与 predefined 动作 extra 中相同。 |
| `invert` | boolean | `true` / `false` | 反选匹配结果。 |

逻辑规则：`{ "type": "logical", "mode": "and|or", "rules": [...] }`，用于组合子规则；`invert` 反转整个匹配。

### 4.4 DNS 规则动作

#### `route` — 把查询转发到指定 DNS 服务器，并终止后续规则匹配。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `race` | boolean | `true` / `false` | 需要 `match_response`（对 logical 规则，位于子规则中）。 与 `speculative` 冲突。 默认情况下，规则逐条按顺序匹配：带 `match_response` 的规则等待其引用的响应，在它被判定之前不会匹配任何后续规则。 启用 `race` 的规则成为竞态规则，不再保持这一顺序：其引用的响应尚未到达时，规则匹配会越过它继续进行，因此竞态规则的匹配相互并行、也与后续规则并行。每条竞态规则在其引用的响应…（1.14.0+） |
| **`server`** | string | — | 目标 DNS 服务器的标签。 （按 tag 引用） |
| `speculative` | boolean | `true` / `false` | 与 `race` 冲突。没有前序竞态规则时无效果。 默认情况下，查询决不与未判定的竞态规则并行发出：已匹配的 `route` 动作扣住其查询，直到所有竞态规则均未匹配后才发送。 启用 `speculative` 后，查询在规则匹配时立即发出、与未判定的竞态规则并行；其响应仅在所有竞态规则均未匹配后才被使用。（1.14.0+） |
| `timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 覆盖匹配查询的 DNS 查询超时时间。 将覆盖 `dns.timeout`。（1.14.0+） |
| `disable_cache` | boolean | `true` / `false` | 在此查询中禁用缓存。 |
| `disable_optimistic_cache` | boolean | `true` / `false` | 在此查询中禁用乐观 DNS 缓存。（1.14.0+） |
| `rewrite_ttl` | integer（0–4294967295） | 整数 | 重写 DNS 回应中的 TTL。 |
| `client_subnet` | string | — | 默认情况下，将带有指定 IP 前缀的 `edns0-subnet` OPT 附加记录附加到每个查询。 如果值是 IP 地址而不是前缀，则会自动附加 `/32` 或 `/128`。 将覆盖 `dns.client_subnet`. |
| `remove_client_subnet` | boolean | `true` / `false` | 移除查询中的 `edns0-subnet` OPT 附加记录，并抑制 `dns.client_subnet`。 与 `client_subnet` 冲突。（1.14.0+） |

#### `evaluate` — 向指定服务器查询并保存响应，供后续 `match_response` 规则使用；不终止规则匹配。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `race` | boolean | `true` / `false` | 需要 `match_response`（对 logical 规则，位于子规则中）。 与 `speculative` 冲突。 默认情况下，规则逐条按顺序匹配：带 `match_response` 的规则等待其引用的响应，在它被判定之前不会匹配任何后续规则。 启用 `race` 的规则成为竞态规则，不再保持这一顺序：其引用的响应尚未到达时，规则匹配会越过它继续进行，因此竞态规则的匹配相互并行、也与后续规则并行。每条竞态规则在其引用的响应…（1.14.0+） |
| **`server`** | string | — | 目标 DNS 服务器的标签。 （按 tag 引用） |
| `tag` | string | — | 已评估响应的标签。 带标签的响应仅能通过 `match_response` 以标签引用； `match_response: true` 引用最近一条无 `tag` 的 `evaluate` 动作的响应。 |
| `speculative` | boolean | `true` / `false` | 与 `race` 冲突。没有前序竞态规则时无效果。 默认情况下，查询决不与未判定的竞态规则并行发出：已匹配的 `route` 动作扣住其查询，直到所有竞态规则均未匹配后才发送。 启用 `speculative` 后，查询在规则匹配时立即发出、与未判定的竞态规则并行；其响应仅在所有竞态规则均未匹配后才被使用。（1.14.0+） |
| `timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 覆盖匹配查询的 DNS 查询超时时间。 将覆盖 `dns.timeout`。（1.14.0+） |
| `disable_cache` | boolean | `true` / `false` | 在此查询中禁用缓存。 |
| `disable_optimistic_cache` | boolean | `true` / `false` | 在此查询中禁用乐观 DNS 缓存。（1.14.0+） |
| `rewrite_ttl` | integer（0–4294967295） | 整数 | 重写 DNS 回应中的 TTL。 |
| `client_subnet` | string | — | 默认情况下，将带有指定 IP 前缀的 `edns0-subnet` OPT 附加记录附加到每个查询。 如果值是 IP 地址而不是前缀，则会自动附加 `/32` 或 `/128`。 将覆盖 `dns.client_subnet`. |
| `remove_client_subnet` | boolean | `true` / `false` | 移除查询中的 `edns0-subnet` OPT 附加记录，并抑制 `dns.client_subnet`。 与 `client_subnet` 冲突。（1.14.0+） |

#### `respond` — 直接返回此前 `evaluate` 保存的响应。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `race` | boolean | `true` / `false` | 需要 `match_response`（对 logical 规则，位于子规则中）。 与 `speculative` 冲突。 默认情况下，规则逐条按顺序匹配：带 `match_response` 的规则等待其引用的响应，在它被判定之前不会匹配任何后续规则。 启用 `race` 的规则成为竞态规则，不再保持这一顺序：其引用的响应尚未到达时，规则匹配会越过它继续进行，因此竞态规则的匹配相互并行、也与后续规则并行。每条竞态规则在其引用的响应…（1.14.0+） |

#### `route-options` — 只设置缓存/TTL/ECS/超时等选项，不改变服务器。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `race` | boolean | `true` / `false` | 需要 `match_response`（对 logical 规则，位于子规则中）。 与 `speculative` 冲突。 默认情况下，规则逐条按顺序匹配：带 `match_response` 的规则等待其引用的响应，在它被判定之前不会匹配任何后续规则。 启用 `race` 的规则成为竞态规则，不再保持这一顺序：其引用的响应尚未到达时，规则匹配会越过它继续进行，因此竞态规则的匹配相互并行、也与后续规则并行。每条竞态规则在其引用的响应…（1.14.0+） |
| `timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 覆盖匹配查询的 DNS 查询超时时间。 将覆盖 `dns.timeout`。（1.14.0+） |
| `disable_cache` | boolean | `true` / `false` | 在此查询中禁用缓存。 |
| `disable_optimistic_cache` | boolean | `true` / `false` | 在此查询中禁用乐观 DNS 缓存。（1.14.0+） |
| `rewrite_ttl` | integer（0–4294967295） | 整数 | 重写 DNS 回应中的 TTL。 |
| `client_subnet` | string | — | 默认情况下，将带有指定 IP 前缀的 `edns0-subnet` OPT 附加记录附加到每个查询。 如果值是 IP 地址而不是前缀，则会自动附加 `/32` 或 `/128`。 将覆盖 `dns.client_subnet`. |
| `remove_client_subnet` | boolean | `true` / `false` | 移除查询中的 `edns0-subnet` OPT 附加记录，并抑制 `dns.client_subnet`。 与 `client_subnet` 冲突。（1.14.0+） |

#### `reject` — 拒绝查询，可返回指定 RCODE。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `race` | boolean | `true` / `false` | 需要 `match_response`（对 logical 规则，位于子规则中）。 与 `speculative` 冲突。 默认情况下，规则逐条按顺序匹配：带 `match_response` 的规则等待其引用的响应，在它被判定之前不会匹配任何后续规则。 启用 `race` 的规则成为竞态规则，不再保持这一顺序：其引用的响应尚未到达时，规则匹配会越过它继续进行，因此竞态规则的匹配相互并行、也与后续规则并行。每条竞态规则在其引用的响应…（1.14.0+） |
| `method` | string | `(空)` / `default` / `drop` / `reply` | - `default`: 返回 REFUSED。、`drop`: 丢弃请求。 默认使用 `default`。 |
| `no_drop` | boolean | `true` / `false` | 如果未启用，则 30 秒内触发 50 次后，`method` 将被暂时覆盖为 `drop`。 当 `method` 设为 `drop` 时不可用。 |

#### `predefined` — 用预定义记录（answer/ns/extra）直接应答。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `race` | boolean | `true` / `false` | 需要 `match_response`（对 logical 规则，位于子规则中）。 与 `speculative` 冲突。 默认情况下，规则逐条按顺序匹配：带 `match_response` 的规则等待其引用的响应，在它被判定之前不会匹配任何后续规则。 启用 `race` 的规则成为竞态规则，不再保持这一顺序：其引用的响应尚未到达时，规则匹配会越过它继续进行，因此竞态规则的匹配相互并行、也与后续规则并行。每条竞态规则在其引用的响应…（1.14.0+） |
| `rcode` | object | 对象 | 响应码。 默认使用 `NOERROR`。 |
| `answer` | string 或 array<string> | — | 用于作为回答响应的文本 DNS 记录列表。 例子: |
| `ns` | string 或 array<string> | — | 用于作为名称服务器响应的文本 DNS 记录列表。 |
| `extra` | string 或 array<string> | — | 用于作为额外记录响应的文本 DNS 记录列表。 |

### 4.5 FakeIP

`fakeip` 服务器需要 `inet4_range`/`inet6_range`；配合路由里的 `resolve`/DNS 规则使用。`dns.reverse_mapping` 控制是否把反查结果写回映射；`cache_file.store_fakeip` 决定是否持久化。

## 5. 公共字段（入站/出站/DNS/服务共用）

### 5.1 监听字段

所有 TCP/UDP 入站（以及需要监听的 service）通用：

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`listen`** | string | — | 监听地址。 |
| `listen_port` | integer（0–65535） | 整数 | 监听端口。 |
| `bind_interface` | string | — | 要绑定到的网络接口。（1.12.0+） |
| `routing_mark` | integer（0–4294967295） 或 string | 整数，或 `0x...` 十六进制字符串 | 设置 netfilter 路由标记。 支持数字 (如 `1234`) 和十六进制字符串 (如 `"0x1234"`)。（1.12.0+） |
| `reuse_addr` | boolean | `true` / `false` | 重用监听地址。（1.12.0+） |
| `netns` | string | — | 设置网络命名空间，名称或路径。（1.14.0+） （按 tag 引用） |
| `tcp_fast_open` | boolean | `true` / `false` | 启用 TCP Fast Open。 |
| `tcp_multi_path` | boolean | `true` / `false` | 需要 Go 1.21。 启用 TCP Multi Path。 |
| `disable_tcp_keep_alive` | boolean | `true` / `false` | 禁用 TCP keep alive。（1.13.0+） |
| `tcp_keep_alive` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 默认值从 `10m` 更改为 `5m`。 TCP keep alive 初始周期。 默认使用 `5m`。（1.13.0+） |
| `tcp_keep_alive_interval` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | TCP keep alive 间隔。 默认使用 `75s`。 |
| `udp_fragment` | boolean | `true` / `false` | 启用 UDP 分段。 |
| `udp_timeout` | 整数/时长 | 整数（纳秒）或时长字符串 | UDP NAT 过期时间。 默认使用 `5m`。 |
| `detour` | string | — | 如果设置，连接将被转发到指定的入站。 需要目标入站支持，参阅 注入支持。 （按 tag 引用） |

`listen` 省略时通常监听所有地址；`listen_port` 省略表示不监听固定端口（对 TUN 无意义）。

### 5.2 拨号字段

所有出站、DNS 服务器、NTP、HTTP 客户端、部分 service/endpoint 通用：

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `detour` | string | — | 上游出站的标签。 启用时，其他拨号字段将被忽略。 （按 tag 引用） |
| `bind_interface` | string | — | 要绑定到的网络接口。 |
| `inet4_bind_address` | string | — | 要绑定的 IPv4 地址。 |
| `inet6_bind_address` | string | — | 要绑定的 IPv6 地址。 |
| `bind_address_no_port` | boolean | `true` / `false` | 绑定到源地址时不保留端口。 这允许在完整的四元组（源 IP、源端口、目标 IP、目标端口）保持唯一的情况下，为多个连接复用同一源端口。（1.13.0+） |
| `protect_path` | string | — | 仅 Android：把底层套接字绑定到指定 VPN 路径（VpnService.protect）。 |
| `routing_mark` | integer（0–4294967295） 或 string | 整数，或 `0x...` 十六进制字符串 | 设置 netfilter 路由标记。 支持数字 (如 `1234`) 和十六进制字符串 (如 `"0x1234"`)。 |
| `reuse_addr` | boolean | `true` / `false` | 重用监听地址。 |
| `netns` | string | — | 设置网络命名空间，名称或路径。 应避免引用 `unshare` 类型的网络命名空间。（1.14.0+） （按 tag 引用） |
| `connect_timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 连接超时，采用 golang 的 Duration 格式。 持续时间字符串是一个可能有符号的序列十进制数，每个都有可选的分数和单位后缀， 例如 "300ms"、"-1.5h" 或 "2h45m"。 有效时间单位为 "ns"、"us"（或 "µs"）、"ms"、"s"、"m"、"h"。 |
| `tcp_fast_open` | boolean | `true` / `false` | 启用 TCP Fast Open。 |
| `tcp_multi_path` | boolean | `true` / `false` | 需要 Go 1.21。 启用 TCP Multi Path。 |
| `disable_tcp_keep_alive` | boolean | `true` / `false` | 禁用 TCP keep alive。（1.13.0+） |
| `tcp_keep_alive` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 默认值从 `10m` 更改为 `5m`。 TCP keep alive 初始周期。 默认使用 `5m`。（1.13.0+） |
| `tcp_keep_alive_interval` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | TCP keep alive 间隔。 默认使用 `75s`。（1.13.0+） |
| `udp_fragment` | boolean | `true` / `false` | 启用 UDP 分段。 |
| `domain_resolver` | string/object | DNS 服务器 tag，或内联 `{ server, ... }` | 用于解析服务器域名的 DNS 服务器标签，或内联解析器对象（见 §5.2）。 |
| `network_strategy` | string | `default` / `fallback` / `hybrid` | 仅在 Android 与 iOS 平台图形客户端中支持，并且需要 `route.auto_detect_interface`。 用于选择网络接口的策略。 可用值：`default`（默认值）：按顺序连接默认网络或 `network_type` 中指定的网络。、`hybrid`：同时连接所有网络或 `network_type` 中指定的网络。、`fallback`：同时连接默认网络或 `network_type` 中指定的首选网络，当…（1.11.0+） |
| `network_type` | 枚举 或 array<枚举> | `cellular` / `ethernet` / `wifi` / `other`（可数组） | 仅在 Android 与 iOS 平台图形客户端中支持，并且需要 `route.auto_detect_interface`。 当使用 `default` 或 `hybrid` 网络策略时要使用的网络类型，或当使用 `fallback` 网络策略时要使用的首选网络类型。 可用值：`wifi`, `cellular`, `ethernet`, `other`。 默认使用设备默认网络。（1.11.0+） |
| `fallback_network_type` | 枚举 或 array<枚举> | `cellular` / `ethernet` / `wifi` / `other`（可数组） | 仅在 Android 与 iOS 平台图形客户端中支持，并且需要 `route.auto_detect_interface`。 当使用 `fallback` 网络策略时，在首选网络不可用或超时的情况下要使用的回退网络类型。 默认使用除首选网络外的所有其他网络。（1.11.0+） |
| `fallback_delay` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 在生成 RFC 6555 快速回退连接之前等待的时间长度。 对于 `domain_strategy`，是在假设之前等待 IPv6 成功的时间量如果设置了 "prefer_ipv4"，则 IPv6 配置错误并回退到 IPv4。 对于 `network_strategy`，对于 `network_strategy`，是在回退到其他接口之前等待连接成功的时间。 仅当 `domain_strategy` 或 `network_strateg… |

`domain_resolver` 既可以是 DNS 服务器 tag，也可以是内联对象：`{ "server": "dns-tag", "strategy": "prefer_ipv4", "timeout": "5s", "disable_cache": false }`。

### 5.3 TLS

入站 TLS 与出站 TLS 共用大部分字段，差别在证书方向：入站配置自己的证书/私钥，出站配置信任的 CA。

#### 入站 TLS（`tls` on inbound）

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `enabled` | boolean | `true` / `false` | 是否启用 TLS。 |
| `server_name` | string | — | 证书校验使用的服务器名，同时作为 SNI 发送（除非为 IP）。 |
| `insecure` | boolean | `true` / `false` | 接受任意服务器证书（有中间人风险）。 |
| `alpn` | string 或 array<string> | — | 支持的应用层协议协商列表，按优先顺序排列。 如果两个对等点都支持 ALPN，则选择的协议将是此列表中的一个，如果没有相互支持的协议则连接将失败。 参阅 Application-Layer Protocol Negotiation。 |
| `min_version` | string | `1.0` / `1.1` / `1.2` / `1.3` | 可接受的最低 TLS 版本。 默认使用 TLS 1.2。 |
| `max_version` | string | `1.0` / `1.1` / `1.2` / `1.3` | 可接受的最大 TLS 版本。 默认情况下，当前最高版本为 TLS 1.3。 |
| `cipher_suites` | string 或 array<string> | — | 启用的 TLS 1.0–1.2 密码套件列表。列表的顺序被忽略。请注意，TLS 1.3 的密码套件是不可配置的。 如果为空，则使用安全的默认列表。默认密码套件可能会随着时间的推移而改变。 |
| `curve_preferences` | string 或 array<string> | 可单值或数组：`P256` / `P384` / `P521` / `X25519` / `X25519MLKEM768` | 支持的密钥交换机制集合。列表的顺序被忽略，密钥交换机制通过 Golang 的内部偏好顺序从此列表中选择。 可用值，同时也是默认列表：`P256`、`P384`、`P521`、`X25519`、`X25519MLKEM768`（1.13.0+） |
| `certificate` | string 或 array<string> | — | 服务器证书链（PEM 行数组），入站时提供给客户端。 |
| `certificate_path` | string | — | 服务器证书链文件路径；文件变化自动重载。 |
| `client_authentication` | string | `no` / `request` / `require-any` / `verify-if-given` / `require-and-verify` | 客户端证书验证模式：`no` / `request` / `require-any` / `verify-if-given` / `require-and-verify`。 |
| `client_certificate` | string 或 array<string> | — | 要求客户端出示的证书链（mTLS 校验用）。 |
| `client_certificate_path` | string 或 array<string> | — | 要求客户端出示的证书链路径。 |
| `client_certificate_public_key_sha256` | string / array | base64 字符串，或字节数组 | 允许的客户端证书公钥 SHA-256（base64）。 |
| `key` | string 或 array<string> | — | 服务器私钥（PEM 行数组）。 |
| `key_path` | string | — | 服务器私钥文件路径。 |
| `kernel_tx` | boolean | `true` / `false` | 使用 kTLS 加速发送（需要 `splice(2)` 且两端均为纯 TCP/TLS）。 |
| `kernel_rx` | boolean | `true` / `false` | 使用 kTLS 加速接收；官方不建议开启。 |
| `handshake_timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | TLS 握手超时。 |
| `certificate_provider` | string / object | 证书提供者 tag，或内联对象 | 按 tag 引用证书提供者（ACME 等）自动签发/加载证书。 |

#### 出站 TLS（`tls` on outbound）

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `enabled` | boolean | `true` / `false` | 是否启用 TLS。 |
| `engine` | string | `go` / `apple` / `windows` | TLS 引擎：`go`（默认）/ `apple` / `windows`；后两者只支持部分字段。 |
| `disable_sni` | boolean | `true` / `false` | 不在 ClientHello 中发送 SNI。 |
| `server_name` | string | — | 校验证书的主机名，同时作为 SNI 发送。 |
| `insecure` | boolean | `true` / `false` | 接受任意服务器证书（有中间人风险）。 |
| `alpn` | string 或 array<string> | — | 支持的应用层协议协商列表，按优先顺序排列。 如果两个对等点都支持 ALPN，则选择的协议将是此列表中的一个，如果没有相互支持的协议则连接将失败。 参阅 Application-Layer Protocol Negotiation。 |
| `min_version` | string | `1.0` / `1.1` / `1.2` / `1.3` | 可接受的最低 TLS 版本。 默认使用 TLS 1.2。 |
| `max_version` | string | `1.0` / `1.1` / `1.2` / `1.3` | 可接受的最大 TLS 版本。 默认情况下，当前最高版本为 TLS 1.3。 |
| `cipher_suites` | string 或 array<string> | — | 启用的 TLS 1.0–1.2 密码套件列表。列表的顺序被忽略。请注意，TLS 1.3 的密码套件是不可配置的。 如果为空，则使用安全的默认列表。默认密码套件可能会随着时间的推移而改变。 |
| `curve_preferences` | string 或 array<string> | 可单值或数组：`P256` / `P384` / `P521` / `X25519` / `X25519MLKEM768` | 支持的密钥交换机制集合。列表的顺序被忽略，密钥交换机制通过 Golang 的内部偏好顺序从此列表中选择。 可用值，同时也是默认列表：`P256`、`P384`、`P521`、`X25519`、`X25519MLKEM768`（1.13.0+） |
| `certificate` | string 或 array<string> | — | 额外信任的 CA/证书链（PEM 行数组），用于校验服务器。 |
| `certificate_path` | string | — | 额外信任的 CA 文件路径；文件变化自动重载。 |
| `certificate_public_key_sha256` | string / array | base64 字符串，或字节数组 | 固定服务器证书公钥的 SHA-256（base64），防中间人。 |
| `client_certificate` | string 或 array<string> | — | 客户端证书链（mTLS）。 |
| `client_certificate_path` | string | — | 客户端证书链路径。 |
| `client_key` | string 或 array<string> | — | 客户端私钥（PEM 行数组）。 |
| `client_key_path` | string | — | 客户端私钥文件路径。 |
| `fragment` | boolean | `true` / `false` | 把 ClientHello 分片发送，绕过基于 SNI 的阻断。 |
| `fragment_fallback_delay` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 分片失败后回退的等待时间。 |
| `record_fragment` | boolean | `true` / `false` | 分片 TLS record。 |
| `spoof` | string | — | 在真实 ClientHello 前注入白名单 SNI 的伪造 ClientHello（需特权）。 |
| `spoof_method` | string | `wrong-sequence` / `wrong-checksum` / `wrong-ack` / `wrong-md5` / `wrong-timestamp` | 伪造方式：`wrong-sequence` / `wrong-checksum` / `wrong-ack` / `wrong-md5` / `wrong-timestamp`。 |
| `kernel_tx` | boolean | `true` / `false` | 使用 kTLS 加速发送。 |
| `kernel_rx` | boolean | `true` / `false` | 使用 kTLS 加速接收。 |
| `handshake_timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | TLS 握手超时。 |
| `utls` | object | 对象 | uTLS 指纹：`enabled` + `fingerprint`（如 `chrome`）。 |

常用组合：`server_name` + `insecure`（出站）；`certificate_path` + `key_path`（入站）；`utls.fingerprint` 模拟浏览器指纹；`reality` 需要 `handshake.server`、`private_key`、`short_id`。

### 5.4 多路复用（multiplex）

#### 入站侧

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `enabled` | boolean | `true` / `false` | 启用多路复用支持。 |
| `padding` | boolean | `true` / `false` | 如果启用，将拒绝非填充连接。 |
| `brutal` | object | 对象，见 §5.6 | 参阅 TCP Brutal。 |

#### 出站侧

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `enabled` | boolean | `true` / `false` | 启用多路复用支持。 |
| `protocol` | string | `h2mux` / `smux` / `yamux` | 多路复用协议 默认使用 h2mux。 |
| `max_connections` | integer | 整数 | 最大连接数量。 与 `max_streams` 冲突。 |
| `min_streams` | integer | 整数 | 在打开新连接之前，连接中的最小多路复用流数量。 与 `max_streams` 冲突。 |
| `max_streams` | integer | 整数 | 在打开新连接之前，连接中的最大多路复用流数量。 与 `max_connections` 和 `min_streams` 冲突。 |
| `padding` | boolean | `true` / `false` | 如果启用，将拒绝非填充连接。 |
| `brutal` | object | 对象，见 §5.6 | 参阅 TCP Brutal。 |

`protocol` 可选 `smux`/`yamux`/`h2mux`/`h3` 等（以文档为准）；`brutal` 是 TCP Brutal 拥塞控制配置。

### 5.5 V2Ray 传输层（transport）

用于 VLESS/VMess/Trojan 等，`type` 取 `http`/`ws`/`quic`/`grpc`/`httpupgrade`。

#### `http`

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `host` | string 或 array<string> | — | 主机域名列表。 如果设置，客户端将随机选择，服务器将验证。 |
| `path` | string | 文件路径（部分字段可为数组） | Warning V2Ray 文档称服务端和客户端的路径必须一致，但实际代码允许客户端向路径添加任何后缀。 sing-box 使用与 V2Ray 相同的行为，但请注意，该行为在 `WebSocket` 和 `HTTPUpgrade` 传输层中不存在。 HTTP 请求路径 服务器将验证。 |
| `method` | string | — | HTTP 请求方法 如果设置，服务器将验证。 |
| `headers` | object | 键值对（值可为字符串或数组） | HTTP 请求的额外标头 如果设置，服务器将写入响应。 |
| `idle_timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 在 HTTP2 服务器中： 指定闲置客户端应在多长时间内使用 GOAWAY 帧关闭。PING 帧不被视为活动。 在 HTTP2 客户端中： 如果连接上没有收到任何帧，指定一段时间后将使用 PING 帧执行健康检查。需要注意的是，PING 响应被视为已接收的帧，因此如果连接上没有其他流量，则健康检查将在每个间隔执行一次。如果值为零，则不会执行健康检查。 默认使用零。 |
| `ping_timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 在 HTTP2 客户端中： 指定发送 PING 帧后，在指定的超时时间内必须接收到响应。如果在指定的超时时间内没有收到 PING 帧的响应，则连接将关闭。默认超时持续时间为 15 秒。 |

#### `ws`

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `path` | string | 文件路径（部分字段可为数组） | Warning V2Ray 文档称服务端和客户端的路径必须一致，但实际代码允许客户端向路径添加任何后缀。 sing-box 使用与 V2Ray 相同的行为，但请注意，该行为在 `WebSocket` 和 `HTTPUpgrade` 传输层中不存在。 HTTP 请求路径 服务器将验证。 |
| `headers` | object | 键值对（值可为字符串或数组） | HTTP 请求的额外标头 如果设置，服务器将写入响应。 |
| `max_early_data` | integer（0–4294967295） | 整数 | 请求中允许的最大有效负载大小。默认启用。 |
| `early_data_header_name` | string | — | 默认情况下，早期数据在路径而不是标头中发送。 要与 Xray-core 兼容，请将其设置为 `Sec-WebSocket-Protocol`。 它需要与服务器保持一致。 |

#### `quic`

_没有额外字段；按对象类型使用 §5.1 监听字段或 §5.2 拨号字段。_

#### `grpc`

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `service_name` | string | — | gRPC 服务名称。 |
| `idle_timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 在 HTTP2 服务器中： 指定闲置客户端应在多长时间内使用 GOAWAY 帧关闭。PING 帧不被视为活动。 在 HTTP2 客户端中： 如果连接上没有收到任何帧，指定一段时间后将使用 PING 帧执行健康检查。需要注意的是，PING 响应被视为已接收的帧，因此如果连接上没有其他流量，则健康检查将在每个间隔执行一次。如果值为零，则不会执行健康检查。 默认使用零。 |
| `ping_timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 在 HTTP2 客户端中： 指定发送 PING 帧后，在指定的超时时间内必须接收到响应。如果在指定的超时时间内没有收到 PING 帧的响应，则连接将关闭。默认超时持续时间为 15 秒。 |
| `permit_without_stream` | boolean | `true` / `false` | 在标准 gRPC 客户端： 如果启用，客户端传输即使没有活动连接也会发送 keepalive ping。如果禁用，则在没有活动连接时，将忽略 `idle_timeout` 和 `ping_timeout`，并且不会发送 keepalive ping。 默认禁用。 |

#### `httpupgrade`

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `host` | string | — | 主机域名列表。 如果设置，客户端将随机选择，服务器将验证。 |
| `path` | string | 文件路径（部分字段可为数组） | Warning V2Ray 文档称服务端和客户端的路径必须一致，但实际代码允许客户端向路径添加任何后缀。 sing-box 使用与 V2Ray 相同的行为，但请注意，该行为在 `WebSocket` 和 `HTTPUpgrade` 传输层中不存在。 HTTP 请求路径 服务器将验证。 |
| `headers` | object | 键值对（值可为字符串或数组） | HTTP 请求的额外标头 如果设置，服务器将写入响应。 |

### 5.6 TCP Brutal、UDP over TCP、QUIC

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `brutal.enabled` | boolean | `true` / `false` | 启用 TCP Brutal（需内核/协议支持）。 |
| `brutal.up_mbps` | integer |  | 上行带宽（Mbps）。 |
| `brutal.down_mbps` | integer |  | 下行带宽（Mbps）。 |
| `udp_over_tcp.enabled` | boolean | `true` / `false` | 把 UDP 封装进 TCP。 |
| `udp_over_tcp.version` | integer | `1` / `2` | UoT 版本；2 支持多路复用。 |

QUIC 类协议（Hysteria/Hysteria2/TUIC/naive）还共享：`initial_packet_size`、`disable_path_mtu_discovery`、`stream_receive_window`、`connection_receive_window`、`max_concurrent_streams`、`keep_alive_period` 等，含义见各协议表。

### 5.7 用户对象

各协议的 `users[]` 元素结构不同，公共字段是 `name`（仅用于标识）。

| 对象 | 字段 | 说明 |
|---|---|---|
| `User`（HTTP/SOCKS/mixed） | `username`、`password` | 代理认证账号。 |
| `VMessUser` | `name`、`uuid`、`alterId` | `alterId` 为 0 表示 AEAD。 |
| `VLESSUser` | `name`、`uuid`、`flow` | `flow` 如 `xtls-rprx-vision`。 |
| `TrojanUser` | `name`、`password` |  |
| `ShadowsocksUser` | `name`、`password` | 2022 方法下密码为 base64 PSK。 |
| `HysteriaUser` | `name`、`auth`、`auth_str` | 二选一。 |
| `Hysteria2User` | `name`、`password` |  |
| `TUICUser` | `name`、`uuid`、`password` |  |
| `AnyTLSUser` | `name`、`password` |  |
| `ShadowTLSUser` | `name`、`password` |  |
| `SnellUser` | `name`、`userkey` |  |

## 6. endpoints — 接口型组件

endpoint 不是普通的“入站/出站”，而是提供三层接口或系统网络能力的组件：WireGuard、Tailscale、OpenVPN、OpenConnect。它们有 `tag`，可被 route 规则当作出站引用，也可被 `domain_resolver`/DNS 使用。

| type | 作用 |
|---|---|
| `wireguard` | WireGuard 接口端点（1.13 起取代旧的 wireguard 出站）。 |
| `tailscale` | Tailscale 端点：登录、接受路由、exit node、advertise 路由。 |
| `openconnect` | OpenConnect 客户端接口：AnyConnect/GlobalProtect/Fortinet/F5/Pulse 等。 |
| `openvpn-client` | OpenVPN 客户端接口（TLS 或静态密钥）。 |
| `openvpn-server` | OpenVPN 服务端接口。 |

### `wireguard` — WireGuard 接口端点（1.13 起取代旧的 wireguard 出站）。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `system` | boolean | `true` / `false` | 使用系统设备。 需要特权且不能与已有系统接口冲突。 |
| `name` | string | — | 为系统接口自定义设备名称。 |
| `mtu` | integer（0–4294967295） | 整数 | WireGuard MTU。 默认使用 1408。 |
| **`address`** | string 或 array<string> | 单值或数组 | 接口的 IPv4/IPv6 地址或地址段的列表。 要分配给接口的 IP（v4 或 v6）地址段列表。 |
| **`private_key`** | string | — | WireGuard 需要 base64 编码的公钥和私钥。 这些可以使用 wg(8) 实用程序生成： 或 `sing-box generate wg-keypair`. |
| `listen_port` | integer（0–65535） | 整数 | 监听端口。 |
| **`peers`** | array<object> | 数组 | WireGuard 对等方的列表。 |
| `udp_timeout` | 时长 | 整数（纳秒）或时长字符串 | UDP NAT 过期时间。 默认使用 `5m`。 |
| `udp_mapping` | string | `(空)` / `endpoint_independent` / `address_dependent` / `address_and_port_dependent` | UDP NAT 映射行为（Linux）：`endpoint_independent` / `address_dependent` / `address_and_port_dependent`。 |
| `udp_filtering` | string | `(空)` / `endpoint_independent` / `address_dependent` / `address_and_port_dependent` | UDP NAT 过滤行为，取值同 `udp_mapping`；空值表示不过滤。 |
| `udp_nat_max` | integer（0–4294967295） | 整数 | 每个 UDP 连接允许的最大 NAT 条目数。 |
| `workers` | integer | 整数 | WireGuard worker 数量。 默认使用 CPU 数量。 |

通用拨号字段见 §5.2。

`peers[]` 元素（`WireGuardPeer`）：

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `address` | string |  | 对等方的 IP 地址。 |
| `port` | integer | 0–65535 | 对等方的 WireGuard 端口，默认 51820。 |
| **`public_key`** | string | base64 | 对等方公钥（必填）。 |
| `pre_shared_key` | string | base64 | 预共享密钥（可选）。 |
| **`allowed_ips`** | string 或 array<string> | CIDR | 允许走该 peer 的目标网段（必填）。 |
| `reserved` | string 或 array<integer> | 0–255 | 保留字段字节（WARP 等需要）。 |
| `persistent_keepalive_interval` | integer | 秒，默认 0 | 保活间隔；0 表示禁用。 |

### `tailscale` — Tailscale 端点：登录、接受路由、exit node、advertise 路由。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `state_directory` | string | — | 存储 Tailscale 状态的目录。 默认使用 `tailscale`。 示例：`$HOME/.tailscale` |
| `auth_key` | string | — | Note 认证密钥不是必需的。默认情况下，sing-box 将记录登录 URL。 用于创建节点的认证密钥。如果节点已经创建（从之前存储的状态），则不使用此字段。 |
| `control_url` | string | — | 协调服务器 URL。 默认使用 `https://controlplane.tailscale.com`。 |
| `ephemeral` | boolean | `true` / `false` | 指示实例是否应注册为临时节点 (https://tailscale.com/s/ephemeral-nodes)。 |
| `hostname` | string | — | 节点的主机名。 默认使用系统主机名。 在 iOS、tvOS 和 Android 上，默认使用设备名称。 示例：`localhost`（1.14.0+） |
| `accept_routes` | boolean | `true` / `false` | 指示节点是否应接受其他节点通告的路由。 |
| `exit_node` | string | — | 要使用的出口节点名称或 IP 地址。 |
| `exit_node_allow_lan_access` | boolean | `true` / `false` | Note 当出口节点没有相应的通告路由时，即使设置了 `exit_node_allow_lan_access`，私有流量也无法路由到出口节点。 指示本地可访问的子网应该直接路由还是通过出口节点路由。 |
| `advertise_routes` | array<string> | 数组 | 通告到 Tailscale 网络的 CIDR 前缀，作为可通过当前节点访问的路由。 示例：`["192.168.1.1/24"]` |
| `advertise_exit_node` | boolean | `true` / `false` | 指示节点是否应将自己通告为出口节点。 |
| `advertise_tags` | string 或 array<string> | — | 为此节点通告的标签，用于 ACL 执行。 示例：`["tag:server"]`（1.13.0+） |
| `listen_port` | integer（0–65535） | 整数 | 监听 WireGuard 和点对点流量的 UDP 端口。 默认自动选择端口。（1.14.0+） |
| `relay_server_port` | integer（0–65535） | 整数 | 监听来自其他 Tailscale 节点的中继连接的端口。（1.13.0+） |
| `relay_server_static_endpoints` | array<string> | 数组 | 为中继服务器通告的静态端点。（1.13.0+） |
| `system_interface` | boolean | `true` / `false` | 为 Tailscale 创建系统 TUN 接口。（1.13.0+） |
| `system_interface_name` | string | — | 自定义 TUN 接口名。默认使用 `tailscale`（macOS 上为 `utun`）。（1.13.0+） |
| `system_interface_mtu` | integer（0–4294967295） | 整数 | 覆盖 TUN 的 MTU。默认使用 Tailscale 自己的 MTU。（1.13.0+） |
| `udp_timeout` | 整数/时长 | 整数（纳秒）或时长字符串 | UDP NAT 过期时间。 默认使用 `5m`。 |
| `ssh_server` | boolean 或 object | — | 在 tailnet 的 TCP 22 端口上运行 Tailscale SSH 服务器。 访问控制由 Tailscale 管理控制台中的 SSH ACL 决定，它将每个连接映射到一个本地用户。该用户如何解析、以及允许哪些用户，取决于平台：Linux 和 macOS：要切换到 sing-box 运行身份以外的用户需要以 root 运行。；Windows：在命令行客户端中，映射到 sing-box 运行身份以外的本地账户的会话将被拒绝。在…（1.14.0+） |
| `taildrop_directory` | string | — | 存储从 tailnet 对等节点接收到的文件的目录。 相对路径基于工作目录解析，与 state_directory 相同。 默认使用 `Taildrop`。（1.14.0+） |

通用拨号字段见 §5.2。

### `openconnect` — OpenConnect 客户端接口：AnyConnect/GlobalProtect/Fortinet/F5/Pulse 等。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `system` | boolean | `true` / `false` | 使用系统接口。 需要权限，且不能与现有系统接口冲突。 禁用时，sing-box 使用内部网络栈。 |
| `name` | string | — | 系统接口的自定义接口名称。 默认使用自动生成的 `oc` 接口名称。 |
| `udp_timeout` | 时长 | 整数（纳秒）或时长字符串 | UDP NAT 过期时间。 默认使用 `5m`。 |
| `udp_mapping` | string | `(空)` / `endpoint_independent` / `address_dependent` / `address_and_port_dependent` | UDP NAT 映射行为（Linux）：`endpoint_independent` / `address_dependent` / `address_and_port_dependent`。 |
| `udp_filtering` | string | `(空)` / `endpoint_independent` / `address_dependent` / `address_and_port_dependent` | UDP NAT 过滤行为，取值同 `udp_mapping`；空值表示不过滤。 |
| `udp_nat_max` | integer（0–4294967295） | 整数 | 每个 UDP 连接允许的最大 NAT 条目数。 |
| **`server`** | string | — | OpenConnect VPN 服务器 HTTPS URL。 省略协议时会添加 `https://`。不支持 URL 用户信息、查询和片段。 |
| `flavor` | string | `anyconnect` / `gp` / `fortinet` / `f5` / `pulse` / `nc` | OpenConnect 协议 flavor，可选值为 `anyconnect`、`gp`、`fortinet`、`f5`、`pulse` 或 `nc`。 默认使用 `anyconnect`。 |
| `username` | string | — | 用于填充匹配认证表单字段的用户名。 |
| `password` | string | — | 用于填充匹配认证表单字段的密码。 |
| `auth_group` | string | — | 认证组，用于在所选 flavor 支持时预选匹配的组、realm、domain 或 gateway 选项。 |
| `cookie` | string | — | 用于跳过凭据提示并直接连接的现有认证会话。 接受的格式取决于 `flavor`：`anyconnect`：`webvpn` 值，或包含 `webvpn` 的分号分隔 cookie 列表。、`gp`：GlobalProtect 认证返回的完整 authenticated query string。、`nc`：`DSID` 值，或包含 `DSID` 的分号分隔 cookie 列表。、`pulse`：原始 Pulse 认证 cookie… |
| `token` | object | 对象 | 用于自动回答匹配 token 字段或进行 HTTP Bearer 认证的 token 配置。 必须设置 `token.secret` 或 `token.secret_path` 之一。 |
| `reported_os` | string | — | 所选 flavor 支持时向 VPN 服务器报告的操作系统标识。 对于 `anyconnect`、`gp` 和 `pulse`，支持的值为 `linux`、`linux-64`、`win`、`mac-intel`、`android` 和 `apple-ios`。 默认值根据系统平台选择：Windows 使用 `win`，macOS 使用 `mac-intel`，Android 使用 `android`，iOS 使用 `apple-i… |
| `user_agent` | string | — | 所选 flavor 支持时向 VPN 服务器报告的 User-Agent。 默认值由 flavor 决定。AnyConnect、Network Connect、Pulse 和 F5 使用 `AnyConnect-compatible OpenConnect VPN Agent v9.21`；GlobalProtect 使用 `PAN GlobalProtect`；Fortinet 使用 `Mozilla/5.0 SV1`。 |
| `version` | string | — | 所选 flavor 支持时，与 `user_agent` 分开报告的客户端版本。 默认使用 `v9.21`。 |
| `local_hostname` | string | — | 所选 flavor 支持时向 VPN 服务器报告的本地主机名。 默认使用系统主机名；无法获取时使用 `localhost`。 |
| `mobile` | object | 对象 | AnyConnect 移动客户端身份。配置时三个字段均为必填。 |
| `csd` | object | 对象 | AnyConnect CSD/host scan 合规性选项。 服务器请求 CSD 时，默认使用内置 CSD 处理。 |
| `hip` | object | 对象 | GlobalProtect HIP 检查和报告选项。 服务器请求 HIP 时，默认使用内置 HIP 报告。 |
| `tncc` | object | 对象 | Network Connect TNCC 合规性选项。 服务器请求 TNCC 时，默认使用内置 TNCC 处理。 |
| `fortinet_host_check` | object | 对象 | Fortinet hostcheck 结果覆盖选项，在服务器要求时提交。 `fortinet_host_check.hostcheck` 为空时禁用。 部分 Fortinet 服务器只会要求可识别的 FortiClient User-Agent 执行 hostcheck。服务器策略有要求时请配置 `user_agent`。 |
| `no_udp` | boolean | `true` / `false` | 禁用 DTLS 或 ESP 辅助数据通道，仅使用 TLS 数据通道。 |
| `dtls_local_port` | integer（0–65535） | 整数 | 直连 DTLS 或 ESP 辅助数据通道使用的本地 UDP 端口。 默认自动选择临时端口。 |
| `compression_disabled` | boolean | `true` / `false` | 禁用 AnyConnect 压缩协商。 默认情况下，当服务器支持时，CSTP 和 DTLS 会协商无状态 `oc-lz4` 和 `lzs` 压缩。 与设置为 `all` 的 `compression_mode` 冲突。 |
| `compression_mode` | string | `stateless` / `all` | AnyConnect 压缩模式，可选值为：`stateless`：声明支持无状态 `oc-lz4` 和 `lzs` 压缩。、`all`：额外声明支持 CSTP 有状态 `deflate` 压缩。 默认使用 `stateless`。 |
| `ipv6_disabled` | boolean | `true` / `false` | 禁用请求和使用 IPv6 隧道配置。 |
| `http_keepalive_disabled` | boolean | `true` / `false` | 在认证和配置请求中禁用 HTTP 连接复用。 |
| `xml_post_disabled` | boolean | `true` / `false` | 禁用 AnyConnect XML POST 认证，并直接使用旧版 GET 流程开始认证。 |
| `external_auth_disabled` | boolean | `true` / `false` | 禁用 AnyConnect、GlobalProtect 和 Fortinet 的 SSO、SAML 等外部浏览器认证。 |
| `password_authentication_disabled` | boolean | `true` / `false` | 如果服务器返回非成功的认证表单，则中止 AnyConnect 认证，与 OpenConnect `--no-passwd` 行为一致。 |
| `tcp_keep_alive_enabled` | boolean | `true` / `false` | 为直接 VPN 服务器连接启用 TCP keep alive。 设置 `tcp_keep_alive` 或 `tcp_keep_alive_interval` 也会启用。启用但未设置这两个时间值时，使用操作系统默认值。 与 `disable_tcp_keep_alive` 冲突。 |
| `pfs` | boolean | `true` / `false` | 要求 TLS 1.2 及更早版本使用具有前向保密性的 TLS 密码套件。 |
| `mtu` | integer（0–4294967295） | 整数 | 首选隧道 MTU。 协商的 MTU 不超过此值。 非零值小于 `576` 时按 `576` 处理。最大值为 `65535`。 |
| `base_mtu` | integer（0–4294967295） | 整数 | 扣除外层 IP、传输和协议开销后，用于计算 AnyConnect、GlobalProtect、F5 和 Fortinet 隧道 MTU 的基础路径 MTU。 默认使用 `1406`。 这些 flavor 会将小于 `1280` 的值按 `1280` 处理。最大值为 `65535`。 |
| `dpd_interval` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 覆盖 Dead Peer Detection 间隔。 默认使用服务器提供或 flavor 特定的间隔。 大于零且小于 `2s` 的值按 `2s` 处理。值不得为负数。 |
| `reconnect_timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 重连尝试失败后允许累计使用的最大退避时间。 默认使用 `300s`。 值不得为负数。 |
| `trojan_interval` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 覆盖 GlobalProtect HIP report 或 Network Connect TNCC check 的执行间隔。 默认使用服务器提供的间隔。服务器未提供时，GlobalProtect 使用 `1h`。 值不得为负数。 |
| `queue_length` | integer（0–4294967295） | 整数 | VPN transport 与隧道接口之间的入站和出站数据包队列长度。 默认使用 `32`。 |
| `allow_insecure_crypto` | boolean | `true` / `false` | 启用旧版 VPN 服务器所需的弱 TLS 和 DTLS 密码套件及 TLS 1.0 兼容性。 默认禁用；未启用时会拒绝低于 TLS 1.2 的版本。 |
| `tls` | object | 对象，见 §5.3 | 该 endpoint 专用的 TLS 配置（字段与通用 TLS 类似，但类型独立）。 |
| `form_entries` | array<object> | 数组 | 认证表单字段覆盖。 设置 `submission_key` 时按该字段匹配，否则按 `form_id` 和 `name` 的组合匹配。后面的匹配项优先。 |

通用拨号字段见 §5.2。

TLS/认证/压缩/路由等嵌套对象字段较多，这里只列直接字段；完整嵌套结构见 schema 或官方 endpoint 文档。

### `openvpn-client` — OpenVPN 客户端接口（TLS 或静态密钥）。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `server` | string | — | OpenVPN 服务器地址。 `server` 和 `servers` 之一必填。 与 `servers` 冲突。 |
| `server_port` | integer（0–65535） | 整数 | OpenVPN 服务器端口。 设置 `server` 时必填。 |
| `system` | boolean | `true` / `false` | 使用系统接口。 需要权限，且不能与现有系统接口冲突。 禁用时，sing-box 使用内部网络栈。 |
| `name` | string | — | 系统接口的自定义接口名称。 默认使用自动生成的 `ovpn` 接口名称。 |
| `mtu` | integer（0–4294967295） | 整数 | OpenVPN 接口 MTU。 为空时使用服务器推送的 MTU；收到服务器配置前使用 `1500`。 |
| `udp_mapping` | string | `(空)` / `endpoint_independent` / `address_dependent` / `address_and_port_dependent` | UDP NAT 映射行为（Linux）：`endpoint_independent` / `address_dependent` / `address_and_port_dependent`。 |
| `udp_filtering` | string | `(空)` / `endpoint_independent` / `address_dependent` / `address_and_port_dependent` | UDP NAT 过滤行为，取值同 `udp_mapping`；空值表示不过滤。 |
| `udp_nat_max` | integer（0–4294967295） | 整数 | 每个 UDP 连接允许的最大 NAT 条目数。 |
| `mode` | string | `tls` / `static_key` | OpenVPN 会话模式，可选值为 `tls` 或 `static_key`。 默认使用 `tls`。 `static_key` 是已弃用的 OpenVPN 模式，不使用 TLS 控制通道且不提供前向保密。 |
| `network` | string | `udp` / `udp4` / `udp6` / `tcp` / `tcp4` / `tcp6` | 默认 OpenVPN 传输网络，可选值为 `udp` 或 `tcp`。 默认使用 `udp`。 该值应用于 `server` 和未单独设置 `network` 的 `servers` 条目。 |
| `servers` | array<object> | 数组 | OpenVPN 服务器列表。 客户端按顺序尝试服务器，并在连接失败时尝试下一台服务器。 `server` 和 `servers` 之一必填。 与 `server` 冲突。 |
| `remote_random` | boolean | `true` / `false` | 连接前随机排列 `servers` 顺序。 默认禁用。 |
| `address` | string 或 array<string> | 单值或数组 | 本地 IPv4 和 IPv6 隧道前缀。 `static_key` 模式至少需要一个地址。在 TLS 模式下该字段可选，并可被服务器推送的地址替换。 |
| `peer_address` | string | — | IPv4 隧道对端地址及 VPN 网关。 在 `static_key` 模式下配置 IPv4 `address` 时必填。 |
| `peer_address_ipv6` | string | — | IPv6 隧道对端地址及 VPN 网关。 在 `static_key` 模式下配置 IPv6 `address` 时必填。 |
| `topology` | string | `net30` / `p2p` / `subnet` | 隧道拓扑，可选值为 `net30`、`p2p` 或 `subnet`。 TLS 模式下为空时使用服务器推送的拓扑。 |
| `username` | string | — | OpenVPN 用户名/密码认证的用户名。 仅在 TLS 模式下可用。 |
| `password` | string | — | OpenVPN 用户名/密码认证的密码。 |
| `auth_retry` | string | `none` / `nointeract` / `interact` | 用户名/密码认证失败后的行为，可选值为 `none`、`nointeract` 或 `interact`。 默认使用 `none`，并将永久认证失败视为终止错误。 `nointeract` 和 `interact` 允许重试认证。 |
| `static_challenge` | string | — | 请求认证响应时显示的静态质询文本。 |
| `static_challenge_echo` | boolean | `true` / `false` | 以明文显示静态质询响应。 |
| `static_key` | string 或 array<string> | — | OpenVPN 静态密钥内容。 在 `static_key` 模式下必填。 与 `static_key_path` 冲突。 |
| `static_key_path` | string | — | OpenVPN 静态密钥路径。 在 `static_key` 模式下未设置 `static_key` 时必填。 与 `static_key` 冲突。 |
| `key_direction` | string | `server` / `client` | 静态密钥方向，可选值为 `server` 或 `client`。 为空时双向使用密钥。仅在 `static_key` 模式下可用。 |
| `tls` | object | 对象，见 §5.3 | 该 endpoint 专用的 TLS 配置（字段与通用 TLS 类似，但类型独立）。 |
| `cipher` | string | — | `static_key` 模式使用的数据通道 cipher。 为空时使用上游静态密钥模式的默认值 `BF-CBC`。静态密钥 cipher 包括 `BF-CBC`、`CAST5-CBC`、`DES-CBC`、`DES-EDE-CBC`、`DES-EDE3-CBC`、 AES-CBC、ARIA-CBC、Camellia-CBC 系列，以及 `SEED-CBC`、`SM4-CBC` 和 `NONE`。 仅在 `static_key` 模… |
| `data_ciphers` | string 或 array<string> | — | 允许的 OpenVPN 数据通道 cipher。 仅在 TLS 模式下可用。 默认使用 `AES-256-GCM`、`AES-128-GCM` 和 `CHACHA20-POLY1305`。 AES-GCM 系列还包括 `AES-192-GCM`。保留的 cipher 包括 AES、ARIA、Camellia、DES、Blowfish、CAST5、SEED 和 SM4 的 CBC、CFB、OFB 形式，以及 `NONE`。CFB 和… |
| `data_ciphers_fallback` | string | — | 用于不支持 cipher 协商的对端的数据通道 cipher。 默认禁用。 仅在 TLS 模式下可用。 |
| `auth` | string | — | OpenVPN 数据通道认证摘要。 默认使用 `SHA1`，仅应用于非 AEAD 数据 cipher 和 `tls_auth`。 |
| `mss_fix` | integer（0–4294967295） | 整数 | OpenVPN UDP packet 的最大大小，用于限制通过隧道发送的 TCP 连接 MSS。 为空时使用上游 OpenVPN 默认值：配置了 `fragment` 时使用其值；否则默认 tunnel MTU 使用 `1492`，自定义 tunnel MTU 使用该 MTU。 |
| `mss_fix_disabled` | boolean | `true` / `false` | 禁用 MSS 限制，包括默认限制。 与 `mss_fix` 和 `mss_fix_mode` 冲突。 |
| `mss_fix_mode` | string | `mtu` / `fixed` | 显式 `mss_fix` 的 OpenVPN MSS 计算模式，`mtu` 或 `fixed` 之一。 空值使用普通的 OpenVPN 封装开销计算。`mtu` 还会计算外层 IP 和 UDP/TCP 传输头、`fixed` 将 `mss_fix` 视为内层 IPv4 数据包大小。 需要 `mss_fix`。 |
| `fragment` | integer（0–4294967295） | 整数 | 用于 OpenVPN 数据通道 fragmentation 的最大 OpenVPN UDP packet 大小。 设为 `0` 时禁用。非零值必须至少为 `68`。 与 TCP 传输冲突。 |
| `replay_window` | integer（0–4294967295） | 整数 | UDP 数据通道重放窗口大小。默认使用 `64`，最大值为 `65536`。 |
| `replay_window_time` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | UDP 数据通道重放窗口时长。默认使用 `15s`，最大值为 `10m`。 该值必须使用整秒。 |
| `compression` | string | `none` / `no` / `lz4` / `lz4-v2` / `stub` / `stub-v2` / `disabled` / `off` | OpenVPN `compress` framing 模式，可选值为 `none`、`no`、`lz4`、`lz4-v2`、`stub`、`stub-v2`、`disabled` 或 `off`。 默认禁用。 |
| `compression_lzo` | string | `none` / `no` / `yes` / `adaptive` / `asym` / `disabled` / `off` | OpenVPN `comp-lzo` 模式，可选值为 `none`、`no`、`yes`、`adaptive`、`asym`、`disabled` 或 `off`。 默认禁用。 |
| `allow_compression` | string | `no` / `asym` / `yes` | 服务器推送的 compression 策略，可选值为 `no`、`asym` 或 `yes`。 默认使用 `no`，仅允许 compression stub framing。`asym` 接受来自服务器的 compressed packet，但不压缩出站 packet。`yes` 是 `asym` 的旧别名。 当设为 `no` 时，与通过 `compression` 或 `compression_lzo` 启用的非 stub com… |
| `route_no_pull` | boolean | `true` / `false` | 忽略服务器推送的 route、DNS 和 DHCP 设置、route metric、`redirect-gateway`、 `redirect-private`、`block-ipv6` 和 `block-outside-dns`。 默认禁用。 |
| `pull_filters` | array<object> | 数组 | 服务器推送选项的有序 pull filter 列表。 应用第一个 `text` 为完整推送选项大小写敏感前缀的 filter。未匹配任何 filter 的选项会被接受。 |
| `routes` | string 或 array<string> | — | sing-box 路由优先选择此 OpenVPN endpoint 的 IPv4 和 IPv6 前缀。 这些 route 会与从服务器接受的 route 一起使用。 |
| `route_gateway` | string | — | 通过 OpenVPN endpoint 路由的 IPv4 gateway。 为空时使用从服务器接收的 VPN gateway。 |
| `route_metric` | integer | 整数 | 通过 OpenVPN endpoint 路由的默认 metric。 设为 `0` 时使用平台默认值。 |
| `redirect_gateway` | boolean | `true` / `false` | 在 sing-box 路由中对所有 IPv4 目的地优先选择 OpenVPN endpoint。 默认禁用。 |
| `redirect_gateway_flags` | string 或 array<string> | — | OpenVPN `redirect-gateway` flag。 `!ipv4` 禁用 IPv4 偏好，`def1` 使用两个 `/1` 前缀表示，`ipv6` 还会优先选择上游特定的 IPv6 前缀。`local`、`autolocal`、`bypass-dhcp` 和 `bypass-dns` 无效果。不支持 `block-local`。 默认为空。 |
| `redirect_private` | boolean | `true` / `false` | 接受 `redirect_gateway_flags`，但不添加默认路由偏好。 默认禁用。 |
| `block_ipv6` | boolean | `true` / `false` | 在本地拒绝 IPv6 流量，而不是通过 VPN 发送。 默认禁用。 |
| `ping_interval` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 客户端未向服务器发送任何 packet 时，发送 data channel ping 的间隔。 服务器推送的 OpenVPN `ping` 值优先于该值。 该值必须使用整秒。 默认禁用。 |
| `ping_restart` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 客户端未收到任何 packet 后重新连接服务器的时间。 服务器推送的 OpenVPN `ping-restart` 值优先于该值。 该值必须使用整秒。 为空时，启用了 pull 的 UDP 连接会使用 `120s`，直到服务器推送其他值。TCP 不使用默认接收超时。 |
| `ping_restart_disabled` | boolean | `true` / `false` | 禁用初始 `120s` UDP 拉取超时和本地配置的 ping 重启超时。 与 `ping_restart` 冲突。 |
| `renegotiate_interval` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | OpenVPN TLS 重新协商间隔。 为空时使用 OpenVPN 默认值 `1h`。 |
| `renegotiate_disabled` | boolean | `true` / `false` | 禁用基于时间的 TLS 重新协商，包括默认间隔。 与 `renegotiate_interval` 冲突。 |
| `renegotiate_bytes` | integer | 整数 | 传输指定字节数后重新协商数据通道密钥。`0` 使用与密码算法相关的 OpenVPN 默认值。 |
| `renegotiate_packets` | integer | 整数 | 传输指定数据包数后重新协商数据通道密钥。`0` 使用与密码算法相关的 OpenVPN 默认值。 |
| `tls_timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | TLS 控制数据包的初始重传超时。为空时使用 OpenVPN 默认值 `2s`。 |
| `handshake_window` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 初始 TLS 握手及每次重新协商的最长允许时间。为空时使用 OpenVPN 默认值 `1m`。 |
| `explicit_exit_notify` | integer（0–4294967295） | 整数 | 关闭 UDP 连接时发送的 OpenVPN exit notification 数量。 Notification 之间间隔一秒。设为 `0` 时禁用。 |
| `udp_timeout` | 整数/时长 | 整数（纳秒）或时长字符串 | UDP NAT 过期时间。 默认使用 `5m`。 |

通用拨号字段见 §5.2。

TLS/认证/压缩/路由等嵌套对象字段较多，这里只列直接字段；完整嵌套结构见 schema 或官方 endpoint 文档。

### `openvpn-server` — OpenVPN 服务端接口。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `system` | boolean | `true` / `false` | 使用系统接口。 需要特权且不能与已有系统接口冲突。 如果禁用，sing-box 将使用内部网络栈。 |
| `name` | string | — | 系统接口的自定义接口名称。 默认使用自动生成的 `ovpn` 接口名称。 |
| `mtu` | integer（0–4294967295） | 整数 | OpenVPN 接口 MTU。 默认使用 `1500`。 |
| `udp_mapping` | string | `(空)` / `endpoint_independent` / `address_dependent` / `address_and_port_dependent` | UDP NAT 映射行为（Linux）：`endpoint_independent` / `address_dependent` / `address_and_port_dependent`。 |
| `udp_filtering` | string | `(空)` / `endpoint_independent` / `address_dependent` / `address_and_port_dependent` | UDP NAT 过滤行为，取值同 `udp_mapping`；空值表示不过滤。 |
| `udp_nat_max` | integer（0–4294967295） | 整数 | 每个 UDP 连接允许的最大 NAT 条目数。 |
| `mode` | string | `tls` / `static_key` | OpenVPN 会话模式，`tls` 或 `static_key` 之一。 默认使用 `tls`。 `static_key` 在没有 TLS 控制信道和前向保密的情况下服务一个对端。 |
| `network` | string | `tcp` / `udp` | OpenVPN 传输网络，`udp` 或 `tcp` 之一。 默认使用 `udp`。 每个端点仅服务一种传输网络；如需同时服务 TCP 与 UDP， 需要配置两个端点并使用互不重叠的 `address` 子网。 |
| `remote` | string | — | UDP `static_key` 服务器的固定远端地址。 在 UDP `static_key` 模式下与 `remote_port` 一起必填。 |
| `remote_port` | integer（0–65535） | 整数 | UDP `static_key` 服务器的固定远端端口。 在 UDP `static_key` 模式下与 `remote` 一起必填。 |
| `max_clients` | integer | 整数 | 已建立与握手中的 TLS 客户端会话的最大数量。 默认使用 `1024`。最大值为 `16777215`。 在 `static_key` 模式下必须为 `0` 或 `1`。 |
| **`address`** | string 或 array<string> | 单值或数组 | OpenVPN 服务器地址前缀列表。 最多支持一个 IPv4 前缀和一个 IPv6 前缀。 前缀地址被分配给服务器接口。掩码后的前缀用作客户端地址池和路由。 第一个 IPv4 和 IPv6 前缀地址用作端点的本地地址。 在 `static_key` 模式下，这些地址是本地隧道前缀，而不是地址池。 |
| `peer_address` | string | — | IPv4 隧道对端地址。 在 `static_key` 模式下配置 IPv4 `address` 时必填。 |
| `peer_address_ipv6` | string | — | IPv6 隧道对端地址。 在 `static_key` 模式下配置 IPv6 `address` 时必填。 |
| `topology` | string | `net30` / `p2p` / `subnet` | 推送给客户端的 OpenVPN topology，`subnet`、`p2p` 或 `net30` 之一。 TLS 模式默认使用 `subnet`，`static_key` 模式默认使用 `p2p`。 |
| `duplicate_cn` | boolean | `true` / `false` | 允许具有相同认证证书 common name 或用户名的多个客户端同时在线。 禁用时，新认证的会话会替换具有相同身份的现有会话，并在可用时复用其 tunnel 地址。 默认禁用。 仅在 TLS 模式下可用。 |
| `users` | array<object> | 数组，元素见 §5.7 | OpenVPN 用户名/密码用户列表。 如果设置，客户端除了通过 `tls.verify_client_certificate` 配置的证书策略外，还必须通过用户名/密码认证。 仅在 TLS 模式下可用。 |
| `static_key` | string 或 array<string> | — | OpenVPN 静态密钥内容。 在 `static_key` 模式下必填。 与 `static_key_path` 冲突。 |
| `static_key_path` | string | — | OpenVPN 静态密钥路径。 在 `static_key` 模式下未设置 `static_key` 时必填。 与 `static_key` 冲突。 |
| `key_direction` | string | `server` / `client` | 静态密钥方向，`server` 或 `client` 之一。 为空时双向使用密钥。按照惯例，服务器使用 `server`，对端使用 `client`。 仅在 `static_key` 模式下可用。 |
| `tls` | object | 对象，见 §5.3 | 该 endpoint 专用的 TLS 配置（字段与通用 TLS 类似，但类型独立）。 |
| `cipher` | string | — | `static_key` 模式使用的数据信道加密方式。 为空时使用上游静态密钥模式的默认值 `BF-CBC`。支持 AES-CBC、ARIA-CBC、Camellia-CBC、DES-CBC、Blowfish-CBC、CAST5-CBC 系列，以及 `SEED-CBC`、`SM4-CBC` 和 `NONE`。 仅在 `static_key` 模式下可用。 |
| `data_ciphers` | string 或 array<string> | — | 允许的 OpenVPN 数据信道加密方式。 默认使用 `AES-256-GCM`、`AES-128-GCM` 和 `CHACHA20-POLY1305`。 AES-GCM 系列还包括 `AES-192-GCM`。保留的 cipher 包括 AES、ARIA、Camellia、DES、Blowfish、CAST5、SEED 和 SM4 的 CBC、CFB、OFB 形式，以及 `NONE`。CFB 和 OFB 仅可用于 TLS 模式。… |
| `data_ciphers_fallback` | string | — | 用于不支持加密方式协商的遗留客户端的 OpenVPN 数据信道加密方式。 等价于 OpenVPN `data-ciphers-fallback`。 默认禁用。 仅在 TLS 模式下可用。 |
| `auth` | string | — | OpenVPN 数据信道认证摘要。 默认使用 `SHA1`，仅对非 AEAD 数据信道加密方式和 `tls_auth` 生效。 |
| `mss_fix` | integer（0–4294967295） | 整数 | 用于限制 TCP MSS 的最大封装数据包大小。默认 MTU 下使用上游默认值 `1492` 计算。 |
| `mss_fix_disabled` | boolean | `true` / `false` | 禁用 MSS 限制，包括默认限制。 |
| `mss_fix_mode` | string | `mtu` / `fixed` | 显式 `mss_fix` 的计算模式，`mtu` 或 `fixed` 之一。需要 `mss_fix`。 |
| `replay_window` | integer（0–4294967295） | 整数 | UDP 数据通道重放窗口大小。默认使用 `64`。 |
| `replay_window_time` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | UDP 重放窗口时长。默认使用 `15s`。该值必须使用整秒。 |
| `push` | object | 对象 | 推送给客户端的选项。 |
| `ping_interval` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 服务器未向客户端发送任何 packet 时，发送 data channel ping 的间隔。 该值应用于服务器。使用 `push.ping_interval` 配置客户端。 该值必须使用整秒。 默认禁用。 |
| `ping_restart` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 服务器未收到任何 packet 后关闭客户端会话的时间。 该值应用于服务器。使用 `push.ping_restart` 配置客户端。 该值必须使用整秒。 默认禁用。 |
| `renegotiate_interval` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | OpenVPN TLS 重协商间隔。 为空时使用 OpenVPN 默认值 `1h`。 仅在 TLS 模式下可用。 |
| `renegotiate_disabled` | boolean | `true` / `false` | 禁用基于时间的 TLS 重协商，包括默认间隔。 仅在 TLS 模式下可用。 |
| `renegotiate_bytes` | integer | 整数 | 传输指定字节数后重新协商数据通道密钥。`0` 使用与密码算法相关的 OpenVPN 默认值。 仅在 TLS 模式下可用。 |
| `renegotiate_packets` | integer | 整数 | 传输指定数据包数后重新协商数据通道密钥。`0` 使用与密码算法相关的 OpenVPN 默认值。 仅在 TLS 模式下可用。 |
| `handshake_window` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 初始 TLS 握手和每次 TLS 重协商允许使用的最长时间。 默认使用 `1m`。 仅在 TLS 模式下可用。 |

通用拨号字段见 §5.2。

TLS/认证/压缩/路由等嵌套对象字段较多，这里只列直接字段；完整嵌套结构见 schema 或官方 endpoint 文档。

## 7. inbounds — 入站

数组元素由 `type` 判别。除 `tun` 外，所有入站都支持 §5.1 的监听字段；带 TLS 的入站还支持 §5.3 的入站 TLS。`tag` 供路由规则与 `detour` 引用。

### `anytls` — AnyTLS 服务端：TLS 隧道上承载多路复用连接，可配置填充方案，目标是降低流量特征。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `tls` | object | 对象，见 §5.3 | TLS 配置（入站 TLS，见 §5.3）。 |
| `users` | array<object> | 数组，元素见 §5.7 | 用户列表；元素字段见 §5.7。 |
| `padding_scheme` | string 或 array<string> | — | AnyTLS 填充方案：字符串或字符串数组。 |

通用监听字段见 §5.1。

### `cloudflared` — Cloudflare Tunnel 客户端入口：内嵌 cloudflared，把隧道流量（TCP/UDP/ICMP）交给 sing-box 路由引擎。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`token`** | string | — | 来自 Cloudflare Zero Trust 仪表板的 Base64 编码隧道令牌 （`Networks → Tunnels → Install connector`）。 |
| `ha_connections` | integer | 整数 | 到 Cloudflare edge 的高可用连接数。 上限为已发现的 edge 地址数量。 |
| `protocol` | string | `auto` / `quic` / `http2` / `h2mux` | edge 连接使用的传输协议。 `quic` `http2` 之一。 |
| `post_quantum` | boolean | `true` / `false` | 在控制连接上启用后量子密钥交换。 |
| `edge_ip_version` | integer | `0` / `4` / `6` | 连接 Cloudflare edge 时使用的 IP 版本。 `0`（自动）`4` `6` 之一。 |
| `datagram_version` | string | `v2` / `v3` | 通过 QUIC 进行 UDP 代理时使用的数据报协议版本。 `v2` `v3` 之一。仅在 `protocol` 为 `quic` 时有效。 |
| `grace_period` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 正在处理的 edge 连接的优雅关闭窗口。 |
| `region` | string | — | Cloudflare edge 区域选择器。 与 `token` 中嵌入的 endpoint 冲突。 |
| `control_dialer` | object | 对象 | 隧道客户端拨向 Cloudflare 控制面时使用的 拨号字段。 |
| `tunnel_dialer` | object | 对象 | 隧道客户端拨向 Cloudflare edge 数据面时使用的 拨号字段。 |

通用监听字段见 §5.1。

### `direct` — 隧道服务器：把监听端口收到的连接原样转发到指定地址/端口，可做简单端口映射。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `network` | string 或 array<string> | 可单值或数组：`tcp` / `udp` | 监听的网络协议，`tcp` `udp` 之一。 默认所有。 |
| `override_address` | string | — | 覆盖连接目标地址。 |
| `override_port` | integer（0–65535） | 整数 | 覆盖连接目标端口。 |

通用监听字段见 §5.1。

### `http` — HTTP/HTTPS 代理服务端：支持 CONNECT、用户认证、可选 TLS。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `users` | array<object> | 数组，元素见 §5.7 | 用户列表；元素字段见 §5.7。 |
| `domain_resolver` | string/object | DNS 服务器 tag，或内联 `{ server, ... }` | 解析监听地址/服务端域名用的 DNS（见 §5.2）。 |
| `set_system_proxy` | boolean | `true` / `false` | 要在无特权的 Android 和 iOS 上工作，请改用 tun.platform.http_proxy。 启动时自动设置系统代理，停止时自动清理。 |
| `tls` | object | 对象，见 §5.3 | TLS 配置（入站 TLS，见 §5.3）。 |

通用监听字段见 §5.1。

### `hysteria` — Hysteria v1 QUIC 服务端（旧协议，保留兼容）。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`up`** | integer 或 string | — | 格式: `[Integer] [Unit]` 例如： `100 Mbps, 640 KBps, 2 Gbps` 支持的单位 (大小写敏感, b = bits, B = bytes, 8b=1B)： |
| **`up_mbps`** | integer | 整数 | 以 Mbps 为单位的 `up, down`。 |
| **`down`** | integer 或 string | — | 格式: `[Integer] [Unit]` 例如： `100 Mbps, 640 KBps, 2 Gbps` 支持的单位 (大小写敏感, b = bits, B = bytes, 8b=1B)： |
| **`down_mbps`** | integer | 整数 | 以 Mbps 为单位的 `up, down`。 |
| `obfs` | string | 对象：`type` 为 `salamander` / `gecko` | 混淆；`type: salamander` + `password`。 |
| `users` | array<object> | 数组，元素见 §5.7 | 用户列表；元素字段见 §5.7。 |
| `tls` | object | 对象，见 §5.3 | TLS 配置（入站 TLS，见 §5.3）。 |
| `idle_timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 在 HTTP2 服务器中： 指定闲置客户端应在多长时间内使用 GOAWAY 帧关闭。PING 帧不被视为活动。 在 HTTP2 客户端中： 如果连接上没有收到任何帧，指定一段时间后将使用 PING 帧执行健康检查。需要注意的是，PING 响应被视为已接收的帧，因此如果连接上没有其他流量，则健康检查将在每个间隔执行一次。如果值为零，则不会执行健康检查。 默认使用零。 |
| `keep_alive_period` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | QUIC 保活周期；默认由协议决定（通常 0/关闭）。 |
| `stream_receive_window` | integer 或 string | 整数或带单位字符串 | QUIC 单条流的接收窗口（字节数或带单位字符串）。 |
| `connection_receive_window` | integer 或 string | 整数或带单位字符串 | QUIC 连接级接收窗口。 |
| `max_concurrent_streams` | integer | 整数 | QUIC 允许的最大并发流数量。 |
| `initial_packet_size` | integer | 整数 | 初始 QUIC 数据包大小。 |
| `disable_path_mtu_discovery` | boolean | `true` / `false` | 禁用 QUIC 路径 MTU 发现。 |

通用监听字段见 §5.1。

### `hysteria2` — Hysteria2 QUIC 服务端：带宽声明、obfs、masquerade、Brutal 拥塞控制。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `up_mbps` | integer | 整数 | 支持的速率，默认不限制。 与 `ignore_client_bandwidth` 冲突。 |
| `down_mbps` | integer | 整数 | 支持的速率，默认不限制。 与 `ignore_client_bandwidth` 冲突。 |
| `obfs` | object | 对象：`type` 为 `salamander` / `gecko` | 混淆；`type: salamander` + `password`。 |
| `users` | array<object> | 数组，元素见 §5.7 | 用户列表；元素字段见 §5.7。 |
| `ignore_client_bandwidth` | boolean | `true` / `false` | 当 `up_mbps` 和 `down_mbps` 未设定时: 命令客户端使用 BBR 拥塞控制算法而不是 Hysteria CC。 当 `up_mbps` 和 `down_mbps` 已设定时: 禁止客户端使用 BBR 拥塞控制算法。 |
| `tls` | object | 对象，见 §5.3 | TLS 配置（入站 TLS，见 §5.3）。 |
| `idle_timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 在 HTTP2 服务器中： 指定闲置客户端应在多长时间内使用 GOAWAY 帧关闭。PING 帧不被视为活动。 在 HTTP2 客户端中： 如果连接上没有收到任何帧，指定一段时间后将使用 PING 帧执行健康检查。需要注意的是，PING 响应被视为已接收的帧，因此如果连接上没有其他流量，则健康检查将在每个间隔执行一次。如果值为零，则不会执行健康检查。 默认使用零。 |
| `keep_alive_period` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | QUIC 保活周期；默认由协议决定（通常 0/关闭）。 |
| `stream_receive_window` | integer 或 string | 整数或带单位字符串 | QUIC 单条流的接收窗口（字节数或带单位字符串）。 |
| `connection_receive_window` | integer 或 string | 整数或带单位字符串 | QUIC 连接级接收窗口。 |
| `max_concurrent_streams` | integer | 整数 | QUIC 允许的最大并发流数量。 |
| `initial_packet_size` | integer | 整数 | 初始 QUIC 数据包大小。 |
| `disable_path_mtu_discovery` | boolean | `true` / `false` | 禁用 QUIC 路径 MTU 发现。 |
| `masquerade` | string 或 object | — | Hysteria2 伪装响应：字符串、文件路径或 HTTP 响应对象。 |
| `bbr_profile` | string | `standard` / `conservative` / `aggressive` | BBR 拥塞控制算法配置，可选 `conservative` `standard` `aggressive`。 默认使用 `standard`。（1.14.0+） |
| `brutal_debug` | boolean | `true` / `false` | 启用 Hysteria Brutal CC 的调试信息日志记录。 |
| `realm` | object | 对象 | Hysteria2 Realm 注册配置（1.14+）。 |

通用监听字段见 §5.1。

### `mixed` — SOCKS4/4a/5 与 HTTP 混合代理服务端，最常用的局域网代理入口。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `users` | array<object> | 数组，元素见 §5.7 | 用户列表；元素字段见 §5.7。 |
| `domain_resolver` | string/object | DNS 服务器 tag，或内联 `{ server, ... }` | 解析监听地址/服务端域名用的 DNS（见 §5.2）。 |
| `set_system_proxy` | boolean | `true` / `false` | 要在无特权的 Android 和 iOS 上工作，请改用 tun.platform.http_proxy。 启动时自动设置系统代理，停止时自动清理。 |
| `tls` | object | 对象，见 §5.3 | TLS 配置（入站 TLS，见 §5.3）。 |

通用监听字段见 §5.1。

### `naive` — NaiveProxy 服务端：在 HTTP/2 或 HTTP/3 上伪装成普通 HTTPS 流量的代理。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `users` | array<object> | 数组，元素见 §5.7 | 用户列表；元素字段见 §5.7。 |
| `network` | string 或 array<string> | 可单值或数组：`tcp` / `udp` | 监听的网络协议，`tcp` `udp` 之一。 默认所有。 |
| `quic_congestion_control` | string | `bbr` / `cubic` / `reno` | Since sing-box 1.13.0 QUIC 拥塞控制算法。 默认使用 `bbr`。 |
| `tls` | object | 对象，见 §5.3 | TLS 配置（入站 TLS，见 §5.3）。 |

通用监听字段见 §5.1。

### `redirect` — Linux redirect（nftables REDIRECT）透明代理入口，通常只接管 TCP。

_没有额外字段；按对象类型使用 §5.1 监听字段或 §5.2 拨号字段。_

通用监听字段见 §5.1。

### `shadowsocks` — Shadowsocks 服务端：支持 AEAD/2022 方法、多用户、目标覆盖。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `network` | string 或 array<string> | 可单值或数组：`tcp` / `udp` | 监听的网络协议，`tcp` `udp` 之一。 默认所有。 |
| `method` | string | `none` / `aes-128-gcm` / `aes-192-gcm` / `aes-256-gcm` / `chacha20-ietf-poly1305` / `xchacha20-ietf-poly1305` / `2022-blake3-aes-128-gcm` / `2022-blake3-aes-256-gcm` / `2022-blake3-chacha20-poly1305` | 加密方法。2022 系列要求 base64 PSK；`none` 表示不加密。 |
| `password` | string | — | 认证密码；Shadowsocks 中还与加密方法共同决定密钥。 |
| `users` | array<object> | 数组，元素见 §5.7 | 用户列表；元素字段见 §5.7。 |
| `destinations` | array<object> | 数组 | 目标覆盖表：把匹配的目标改写到其它服务器/端口。 |
| `multiplex` | object | 对象，见 §5.4 | 入站多路复用（见 §5.4）。 |
| `managed` | boolean | `true` / `false` | 默认为 `false`。当该入站需要由 SSM API 管理用户时必须启用此字段。 |

通用监听字段见 §5.1。

### `shadowtls` — ShadowTLS 服务端：先进行真实 TLS 握手再切换协议，支持 v1/v2/v3。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `version` | integer | `1` / `2` / `3` | ShadowTLS 协议版本。 |
| `password` | string | — | ShadowTLS 密码。 仅在 ShadowTLS 协议版本 2 中可用。 |
| `users` | array<object> | 数组，元素见 §5.7 | 用户列表；元素字段见 §5.7。 |
| `handshake` | object | 对象 | ShadowTLS 握手目标（伪装成哪个 TLS 站点）。 |
| **`handshake_for_server_name`** | object | 对象 | 对于特定服务器名称的握手服务器地址和 拨号参数。 仅在 ShadowTLS 协议版本 2/3 中可用。 |
| `strict_mode` | boolean | `true` / `false` | ShadowTLS 严格模式。 仅在 ShadowTLS 协议版本 3 中可用。 |
| `wildcard_sni` | string | `(空)` / `off` / `authed` / `all` | ShadowTLS 通配符 SNI 模式。 可用值：`off`：（默认）禁用。、`authed`：已认证的连接的目标将被重写为 `(servername):443`。、`all`：所有连接的目标将被重写为 `(servername):443`。 此外，匹配 `handshake_for_server_name` 的连接不受影响。 仅在 ShadowTLS 协议 3 中可用。（1.12.0+） |

通用监听字段见 §5.1。

### `snell` — Snell v5/v6 服务端，必须显式指定 `version`（v5 复用 v4 线协议，v6 为流量整形）。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`version`** | integer | `5` / `6` | Snell 协议版本，`5` `6` 之一。 版本 `5` 支持 HTTP 混淆（`obfs_mode`）；版本 `6` 以流量整形（`mode`）取而代之，并要求 `psk` 长度为 12 到 255 字节。 Note 由于我们有意不支持 Snell v5 的 QUIC 代理模式，v5 的线路协议实际上与 v4 没有区别， 因此不提供独立的 v4 服务器和 v5 客户端。 |
| **`psk`** | string | — | 预共享密钥。 |
| `users` | array<object> | 数组，元素见 §5.7 | 用户列表；元素字段见 §5.7。 |
| `obfs_mode` | string | `none` / `http` / `tls` | 仅版本 5 HTTP 混淆模式，`none` `http` 之一。 默认为 `none`。 |
| `mode` | string | `default` / `unshaped` / `unsafe-raw` | 仅版本 6 流量整形模式，`default` `unshaped` `unsafe-raw` 之一。 默认为 `default`。 |

通用监听字段见 §5.1。 必须同时给出 `version`。

`version: 5` 复用 v4 线协议（HTTP 混淆用 `obfs_mode`）；`version: 6` 使用流量整形 `mode`，并要求 `psk` 长度 12–255 字节。

### `socks` — SOCKS4/4a/5 服务端，可选用户名/密码认证。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `users` | array<object> | 数组，元素见 §5.7 | 用户列表；元素字段见 §5.7。 |
| `domain_resolver` | string/object | DNS 服务器 tag，或内联 `{ server, ... }` | 解析监听地址/服务端域名用的 DNS（见 §5.2）。 |

通用监听字段见 §5.1。

### `tproxy` — Linux TProxy 透明代理入口，可同时接管 TCP 与 UDP。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `network` | string 或 array<string> | 可单值或数组：`tcp` / `udp` | 监听的网络协议，`tcp` `udp` 之一。 默认所有。 |
| `udp_mapping` | string | `(空)` / `endpoint_independent` / `address_dependent` / `address_and_port_dependent` | UDP NAT 映射行为（Linux）：`endpoint_independent` / `address_dependent` / `address_and_port_dependent`。 |
| `udp_filtering` | string | `(空)` / `endpoint_independent` / `address_dependent` / `address_and_port_dependent` | UDP NAT 过滤行为，取值同 `udp_mapping`；空值表示不过滤。 |
| `udp_nat_max` | integer（0–4294967295） | 整数 | 每个 UDP 连接允许的最大 NAT 条目数。 |

通用监听字段见 §5.1。

### `trojan` — Trojan 服务端：TLS 上的密码认证，支持 fallback、多路复用、V2Ray 传输层。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `users` | array<object> | 数组，元素见 §5.7 | 用户列表；元素字段见 §5.7。 |
| `tls` | object | 对象，见 §5.3 | TLS 配置（入站 TLS，见 §5.3）。 |
| `fallback` | object | 对象 | TLS 握手失败/非匹配协议时的回落目标。 |
| `fallback_for_alpn` | object | 对象 | 按 ALPN 分流的回落目标表。 |
| `multiplex` | object | 对象，见 §5.4 | 入站多路复用（见 §5.4）。 |
| `transport` | object | 对象，见 §5.5 | V2Ray 传输层（见 §5.5）。 |

通用监听字段见 §5.1。

### `tuic` — TUIC v5 QUIC 服务端：0-RTT、UDP 中继、拥塞控制可选。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `users` | array<object> | 数组，元素见 §5.7 | 用户列表；元素字段见 §5.7。 |
| `congestion_control` | string | `cubic` / `new_reno` / `bbr` | QUIC 拥塞控制算法 可选值: `cubic`, `new_reno`, `bbr` 默认使用 `cubic`。 |
| `auth_timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 服务器等待客户端发送认证命令的时间 默认使用 `3s`。 |
| `zero_rtt_handshake` | boolean | `true` / `false` | 在客户端启用 0-RTT QUIC 连接握手 这对性能影响不大，因为协议是完全复用的 强烈建议禁用此功能，因为它容易受到重放攻击。 请参阅 Attack of the clones |
| `heartbeat` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 发送心跳包以保持连接存活的时间间隔 默认使用 `10s`。 |
| `tls` | object | 对象，见 §5.3 | TLS 配置（入站 TLS，见 §5.3）。 |
| `idle_timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 在 HTTP2 服务器中： 指定闲置客户端应在多长时间内使用 GOAWAY 帧关闭。PING 帧不被视为活动。 在 HTTP2 客户端中： 如果连接上没有收到任何帧，指定一段时间后将使用 PING 帧执行健康检查。需要注意的是，PING 响应被视为已接收的帧，因此如果连接上没有其他流量，则健康检查将在每个间隔执行一次。如果值为零，则不会执行健康检查。 默认使用零。 |
| `keep_alive_period` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | QUIC 保活周期；默认由协议决定（通常 0/关闭）。 |
| `stream_receive_window` | integer 或 string | 整数或带单位字符串 | QUIC 单条流的接收窗口（字节数或带单位字符串）。 |
| `connection_receive_window` | integer 或 string | 整数或带单位字符串 | QUIC 连接级接收窗口。 |
| `max_concurrent_streams` | integer | 整数 | QUIC 允许的最大并发流数量。 |
| `initial_packet_size` | integer | 整数 | 初始 QUIC 数据包大小。 |
| `disable_path_mtu_discovery` | boolean | `true` / `false` | 禁用 QUIC 路径 MTU 发现。 |

通用监听字段见 §5.1。

### `tun` — 虚拟网卡入口：创建 tun 接口，结合 `auto_route`/`auto_redirect` 接管本机与局域网流量。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `interface_name` | string | — | 虚拟设备名称，默认自动选择。 |
| `mtu` | integer（0–4294967295） | 整数 | 最大传输单元。 |
| **`address`** | string 或 array<string> | 单值或数组 | tun 接口的 IPv4 和 IPv6 前缀。（1.10.0+） |
| `dns_mode` | string | `disabled` / `native` / `hijack` | TUN 接口上 DNS 的处理方式。 启用 `auto_route` 时默认使用 `hijack`，否则默认使用 `disabled`。 `hijack` 在 `native` 之上额外执行： Linux：发往本机接口地址（如 `127.0.0.53` 或本机 LAN 接口 IP）的 DNS 不会被劫持。；未启用 `auto_redirect` 时：发往直连子网的 53 端口流量也会经由 TUN 路由。；启用 `auto_redir…（1.14.0+） |
| `dns_address` | string 或 array<string> | — | `dns_mode` 使用的 DNS 服务器地址列表。 未设置时，使用 `address` 中第一个 IPv4 和 IPv6 条目的下一个地址， 发往该地址的连接按 `hijack-dns` 路由动作处理。 设置后，请配置 `hijack-dns` 路由规则以处理发往这些地址的 DNS 流量。（1.14.0+） |
| `auto_route` | boolean | `true` / `false` | 设置到 Tun 的默认路由。 为避免流量环回，请设置 `route.auto_detect_interface` 或 `route.default_interface` 或 `outbound.bind_interface`。 与 Android VPN 一起使用 VPN 默认优先于 tun。要使 tun 经过 VPN，启用 `route.override_android_vpn`。 也启用 `auto_redirect` 在 Li… |
| `iproute2_table_index` | integer | 整数 | `auto_route` 生成的 iproute2 路由表索引。 默认使用 `2022`。（1.10.0+） |
| `iproute2_rule_index` | integer | 整数 | `auto_route` 生成的 iproute2 规则起始索引。 默认使用 `9000`。（1.10.0+） |
| `auto_redirect` | boolean | `true` / `false` | 通过使用 nftables 改善 TUN 路由和性能。 在 Linux 上始终推荐使用 `auto_redirect`，它提供更好的路由、更高的性能（优于 tproxy），并避免了 TUN 和 Docker 桥接网络之间的冲突。 预匹配需要内核支持 nfqueue（`nfnetlink_queue`）。 `auto_redirect` 在 Android 上通过图形客户端的 root 服务或 root shell 得到完整支持，包括…（1.10.0+） |
| `auto_redirect_input_mark` | integer（0–4294967295） 或 string | 整数，或 `0x...` 十六进制字符串 | `auto_redirect` 使用的连接输入标记。 默认使用 `0x2023`（Android 上为 `0x400000`）。（1.10.0+） |
| `auto_redirect_output_mark` | integer（0–4294967295） 或 string | 整数，或 `0x...` 十六进制字符串 | `auto_redirect` 使用的连接输出标记。 默认使用 `0x2024`（Android 上为 `0x200000`）。（1.10.0+） |
| `auto_redirect_reset_mark` | integer（0–4294967295） 或 string | 整数，或 `0x...` 十六进制字符串 | `auto_redirect` 预匹配使用的连接重置标记。 默认使用 `0x2025`（Android 上为 `0x600000`）。（1.13.0+） |
| `auto_redirect_nfqueue` | integer（0–65535） | 整数 | `auto_redirect` 预匹配使用的 NFQueue 编号。 默认使用 `100`。（1.13.0+） |
| `auto_redirect_iproute2_fallback_rule_index` | integer | 整数 | `auto_redirect` 生成的 iproute2 回退规则索引。 此规则在系统默认规则（32766: main，32767: default）之后检查， 仅当系统路由表中未找到路由时才将流量路由到 sing-box 路由表。 默认使用 `32768`。（1.12.18+） |
| `exclude_mptcp` | boolean | `true` / `false` | 由于协议限制，MPTCP 无法被透明代理。 此类流量通常由 Apple 系统创建。 启用时，MPTCP 连接将绕过 sing-box 直接连接，否则，将被拒绝以避免错误。（1.13.0+） |
| `loopback_address` | string 或 array<string> | — | 环回地址是用于使指向指定地址的 TCP 连接连接到来源地址的。 将选项值设置为 `10.7.0.1` 可实现与 SideStore/StosVPN 相同的行为。 当启用 `auto_redirect` 时，可以作为网关为局域网设备（而不仅仅是本地）实现相同的行为。（1.12.0+） |
| `strict_route` | boolean | `true` / `false` | 当启用 `auto_route` 时，强制执行严格的路由规则： 在 Linux 中：使不支持的网络不可达。；出于历史遗留原因，当未启用 `strict_route` 或 `auto_redirect` 时，所有 ICMP 流量将不会通过 TUN。；当启用 `auto_redirect` 时，`strict_route` 也影响 `SO_BINDTODEVICE` 流量： 启用：`SO_BINDTODEVICE` 流量被重定向通过 s… |
| `route_address` | string 或 array<string> | — | 设置到 Tun 的自定义路由。（1.10.0+） |
| `route_address_set` | string 或 array<string> | — | `auto_redirect` 预匹配：匹配规则集中目标 IP 的流量进入 sing-box 路由，未匹配的绕过。 |
| `route_exclude_address` | string 或 array<string> | — | 设置到 Tun 的排除自定义路由。（1.10.0+） |
| `route_exclude_address_set` | string 或 array<string> | — | `auto_redirect` 预匹配：匹配规则集中目标 IP 的流量绕过 sing-box（本项目用 `geoip-cn` 做国内直连）。 |
| `include_interface` | string 或 array<string> | — | 接口规则仅在 Linux 下被支持，并且需要 `auto_route`。 限制被路由的接口。默认不限制。 与 `exclude_interface` 冲突。 |
| `exclude_interface` | string 或 array<string> | — | 当 `strict_route` 启用，到被排除接口的回程流量将不会被自动排除，因此也要添加它们（例：`br-lan` 与 `pppoe-wan`）。 排除路由的接口。 与 `include_interface` 冲突。 |
| `include_uid` | integer（0–4294967295） 或 array<integer（0–4294967295）> | — | UID 规则仅在 Linux 下被支持，并且需要 `auto_route`。 限制被路由的用户。默认不限制。 |
| `include_uid_range` | string 或 array<string> | — | 限制被路由的用户范围。 |
| `exclude_uid` | integer（0–4294967295） 或 array<integer（0–4294967295）> | — | 排除路由的用户。 |
| `exclude_uid_range` | string 或 array<string> | — | 排除路由的用户范围。 |
| `include_android_user` | integer 或 array<integer> | — | Android 用户和应用规则仅在 Android 下被支持，并且需要 `auto_route`。 限制被路由的 Android 用户。 |
| `include_package` | string 或 array<string> | — | 限制被路由的 Android 应用包名。 |
| `exclude_package` | string 或 array<string> | — | 排除路由的 Android 应用包名。 |
| `include_mac_address` | string 或 array<string> | — | 限制被路由的 MAC 地址。默认不限制。 与 `exclude_mac_address` 冲突。（1.14.0+） |
| `exclude_mac_address` | string 或 array<string> | — | 排除路由的 MAC 地址。 与 `include_mac_address` 冲突。（1.14.0+） |
| `udp_mapping` | string | `(空)` / `endpoint_independent` / `address_dependent` / `address_and_port_dependent` | UDP NAT 映射行为（Linux）：`endpoint_independent` / `address_dependent` / `address_and_port_dependent`。 |
| `udp_filtering` | string | `(空)` / `endpoint_independent` / `address_dependent` / `address_and_port_dependent` | UDP NAT 过滤行为，取值同 `udp_mapping`；空值表示不过滤。 |
| `udp_nat_max` | integer（0–4294967295） | 整数 | 每个 UDP 连接允许的最大 NAT 条目数。 |
| `stack` | string | `system` / `gvisor` / `mixed` | TUN 的 TCP/IP 栈：`system` / `gvisor` / `mixed`（1.15 起废弃、1.17 移除；1.14.4 仍可用）。 |
| `platform` | object | 对象 | 平台相关 TUN 选项（如 HTTP 代理）。 |

通用监听字段见 §5.1。

TUN 是唯一没有 `listen` 的入站：`address` 必填（IPv4/IPv6 前缀）；`auto_route` 装默认路由，`auto_redirect` 注入 nftables 规则接管转发流量；`dns_mode` 取 `disabled`/`native`/`hijack`，`hijack` 会劫持 53 端口到内部 DNS。`route_exclude_address_set` 让命中的目标 IP 在 nftables 层直接绕过 TUN（本项目用于国内直连）。

### `vless` — VLESS 服务端：无状态轻量协议，常与 TLS/REALITY、V2Ray 传输层组合。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `users` | array<object> | 数组，元素见 §5.7 | 用户列表；元素字段见 §5.7。 |
| `tls` | object | 对象，见 §5.3 | TLS 配置（入站 TLS，见 §5.3）。 |
| `multiplex` | object | 对象，见 §5.4 | 入站多路复用（见 §5.4）。 |
| `transport` | object | 对象，见 §5.5 | V2Ray 传输层（见 §5.5）。 |

通用监听字段见 §5.1。

### `vmess` — VMess 服务端：V2Ray 的带版本、可加密协议。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `users` | array<object> | 数组，元素见 §5.7 | 用户列表；元素字段见 §5.7。 |
| `tls` | object | 对象，见 §5.3 | TLS 配置（入站 TLS，见 §5.3）。 |
| `multiplex` | object | 对象，见 §5.4 | 入站多路复用（见 §5.4）。 |
| `transport` | object | 对象，见 §5.5 | V2Ray 传输层（见 §5.5）。 |

通用监听字段见 §5.1。

## 8. outbounds — 出站

数组元素由 `type` 判别；`selector`/`urltest` 通过 `outbounds` 引用其它出站的 tag。所有出站都支持 §5.2 的拨号字段。**1.13 起 `wireguard` 与 `dns` 出站已移除**：WireGuard 用 `endpoints[].type=wireguard` 代替，DNS 出站用内部 DNS 或 `direct` 代替。

### `anytls` — AnyTLS 客户端：连接 AnyTLS 服务端，TLS 上多路复用。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`server`** | string | — | 服务器地址。 |
| **`server_port`** | integer（0–65535） | 整数 | 服务器端口。 |
| `tls` | object | 对象，见 §5.3 | TLS 配置（出站 TLS，见 §5.3）。 |
| **`password`** | string | — | AnyTLS 密码。 |
| `idle_session_check_interval` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 检查空闲会话的时间间隔。默认值：30秒。 |
| `idle_session_timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 在检查中，关闭闲置时间超过此值的会话。默认值：30秒。 |
| `min_idle_session` | integer | 整数 | 在检查中，至少前 `n` 个空闲会话保持打开状态。默认值：`n`=0 |
| `client_metadata` | string | — | 参阅 AnyTLS 客户端元数据。（1.13.16+） |

通用拨号字段见 §5.2。

### `block` — 拒绝/黑洞出站：命中它的连接全部失败。

_没有额外字段；按对象类型使用 §5.1 监听字段或 §5.2 拨号字段。_

通用拨号字段见 §5.2。

`block` 没有可配置字段；命中它的连接会立即失败。

### `bridge` — L3 直连出站：把 TUN/endpoint 的三层流量从本机网络接口直接发出（需要特权）。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `interface` | string | — | 转发流量流出的网络接口名称。 默认使用默认接口。 |
| `bridge_name` | string | — | 自定义 bridge TUN 接口名前缀，默认使用 `bridge`。 在 Apple 平台上无效。 |
| `iproute2_table_index` | integer | 整数 | Linux iproute2 路由表索引。 默认使用 `2200` + 实例索引。 |
| `iproute2_rule_index` | integer | 整数 | Linux iproute2 规则起始索引。 默认使用 `100`。 |

通用拨号字段见 §5.2。

### `direct` — 直连出站：不经过代理，可绑定接口、源地址、路由标记。

_没有额外字段；按对象类型使用 §5.1 监听字段或 §5.2 拨号字段。_

通用拨号字段见 §5.2。

### `http` — HTTP/HTTPS 代理客户端（支持 CONNECT）。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`server`** | string | — | 服务器地址。 |
| **`server_port`** | integer（0–65535） | 整数 | 服务器端口。 |
| `username` | string | — | Basic 认证用户名。 |
| `password` | string | — | Basic 认证密码。 |
| `tls` | object | 对象，见 §5.3 | TLS 配置（出站 TLS，见 §5.3）。 |
| `path` | string | 文件路径（部分字段可为数组） | HTTP 请求路径。 |
| `headers` | object | 键值对（值可为字符串或数组） | HTTP 请求的额外标头。 |

通用拨号字段见 §5.2。

### `hysteria` — Hysteria v1 QUIC 客户端（旧协议）。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`server`** | string | — | 服务器地址。 |
| **`server_port`** | integer（0–65535） | 整数 | 服务器端口。 |
| `server_ports` | string 或 array<string> | 范围字符串（`1000:2000`），或数组 | 端口跳跃范围，如 `1000:2000` 或数组。 |
| `hop_interval` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 端口跳跃间隔。 |
| `up` | integer 或 string | — | 上行带宽（整数 Mbps，或旧式字符串）。 |
| **`up_mbps`** | integer | 整数 | 以 Mbps 为单位的 `up, down`。 |
| `down` | integer 或 string | — | 下行带宽。 |
| **`down_mbps`** | integer | 整数 | 以 Mbps 为单位的 `up, down`。 |
| `obfs` | string | 对象：`type` 为 `salamander` / `gecko` | 混淆配置。 |
| `auth` | string 或 array<integer（0–255）> | — | base64 编码的认证密码。 |
| `auth_str` | string | — | 认证密码。 |
| `network` | string 或 array<string> | 可单值或数组：`tcp` / `udp` | 限制使用的网络：`tcp` / `udp`（可数组）。 |
| `tls` | object | 对象，见 §5.3 | TLS 配置（出站 TLS，见 §5.3）。 |
| `idle_timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 空闲超时。 |
| `keep_alive_period` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | QUIC 保活周期；默认由协议决定（通常 0/关闭）。 |
| `stream_receive_window` | integer 或 string | 整数或带单位字符串 | QUIC 单条流的接收窗口（字节数或带单位字符串）。 |
| `connection_receive_window` | integer 或 string | 整数或带单位字符串 | QUIC 连接级接收窗口。 |
| `max_concurrent_streams` | integer | 整数 | QUIC 允许的最大并发流数量。 |
| `initial_packet_size` | integer | 整数 | 初始 QUIC 数据包大小。 |
| `disable_path_mtu_discovery` | boolean | `true` / `false` | 禁用 QUIC 路径 MTU 发现。 |

通用拨号字段见 §5.2。

### `hysteria2` — Hysteria2 QUIC 客户端：obfs、带宽、Brutal、端口跳跃。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`server`** | string | — | 服务器地址。 与 `realm` 冲突。 |
| **`server_port`** | integer（0–65535） | 整数 | 服务器端口。 如果设置了 `server_ports`，则忽略此项。 与 `realm` 冲突。 |
| `server_ports` | string 或 array<string> | 范围字符串（`1000:2000`），或数组 | 端口跳跃范围，如 `1000:2000` 或数组。 |
| `hop_interval` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 端口跳跃间隔。 |
| `hop_interval_max` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 最大端口跳跃间隔，用于随机化。 如果设置，实际跳跃间隔将在 `hop_interval` 和 `hop_interval_max` 之间随机选择。（1.14.0+） |
| `up_mbps` | integer | 整数 | 最大带宽。 如果为空，将使用 BBR 拥塞控制算法而不是 Hysteria CC。 |
| `down_mbps` | integer | 整数 | 最大带宽。 如果为空，将使用 BBR 拥塞控制算法而不是 Hysteria CC。 |
| `obfs` | object | 对象：`type` 为 `salamander` / `gecko` | 混淆配置。 |
| `password` | string | — | 认证密码。 |
| `network` | string 或 array<string> | 可单值或数组：`tcp` / `udp` | 限制使用的网络：`tcp` / `udp`（可数组）。 |
| `tls` | object | 对象，见 §5.3 | TLS 配置（出站 TLS，见 §5.3）。 |
| `idle_timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 空闲超时。 |
| `keep_alive_period` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | QUIC 保活周期；默认由协议决定（通常 0/关闭）。 |
| `stream_receive_window` | integer 或 string | 整数或带单位字符串 | QUIC 单条流的接收窗口（字节数或带单位字符串）。 |
| `connection_receive_window` | integer 或 string | 整数或带单位字符串 | QUIC 连接级接收窗口。 |
| `max_concurrent_streams` | integer | 整数 | QUIC 允许的最大并发流数量。 |
| `initial_packet_size` | integer | 整数 | 初始 QUIC 数据包大小。 |
| `disable_path_mtu_discovery` | boolean | `true` / `false` | 禁用 QUIC 路径 MTU 发现。 |
| `bbr_profile` | string | `standard` / `conservative` / `aggressive` | BBR 拥塞控制算法配置，可选 `conservative` `standard` `aggressive`。 默认使用 `standard`。（1.14.0+） |
| `brutal_debug` | boolean | `true` / `false` | 启用 Hysteria Brutal CC 的调试信息日志记录。 |
| `disable_chrome_parrot` | boolean | `true` / `false` | 禁用 Chrome QUIC 指纹模仿。 如果没有禁用，客户端的 QUIC 握手将被构造为模仿 Chrome，使 Hysteria 流量更难通过握手指纹识别。 为了与 Chrome 一致，客户端使用 Chrome 自己的 QUIC 参数，其覆盖部分设置： `idle_timeout` 固定为 30 秒，`max_concurrent_streams` 与 `initial_packet_size` 被替换为 Chrome 的值， 接…（1.14.0+） |
| `realm` | object | 对象 | Hysteria2 Realm 连接配置（1.14+）。 |

通用拨号字段见 §5.2。

### `naive` — NaiveProxy 客户端：HTTP/2 或 HTTP/3 之上的代理。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`server`** | string | — | 服务器地址。 |
| **`server_port`** | integer（0–65535） | 整数 | 服务器端口。 |
| `username` | string | — | 认证用户名。 |
| `password` | string | — | 认证密码。 |
| `insecure_concurrency` | integer | 整数 | 并发隧道连接数。多连接使隧道更容易被流量分析检测，违背 NaiveProxy 抵抗流量分析的设计目的。 |
| `extra_headers` | object | 键值对（值可为字符串或数组） | HTTP 请求中发送的额外头部。 |
| `stream_receive_window` | integer 或 string | 整数或带单位字符串 | 流量控制窗口。 当 `quic` 启用时，它设置 QUIC 初始流接收窗口，默认使用 `6 MB`。 否则，它设置 HTTP/2 会话接收窗口，流接收窗口被设置为它的一半，在 iOS 上默认使用 `4 MB`，在其他平台上默认使用 `128 MB`。 |
| `udp_over_tcp` | boolean 或 object | `true` / `false`，或 `{ enabled, version }` | UDP over TCP 配置。 参阅 UDP Over TCP。 |
| `quic` | boolean | `true` / `false` | 使用 QUIC 代替 HTTP/2。 |
| `quic_congestion_control` | string | `bbr` / `bbr2` / `cubic` / `reno` | QUIC 拥塞控制算法。 默认使用 `cubic`（NaiveProxy 基于的 Chromium 的默认值）。 |
| `quic_session_receive_window` | integer 或 string | 整数或带单位字符串 | 仅在 `quic` 启用时使用。 QUIC 初始会话接收窗口。 默认使用 `15 MB`。 |
| `tls` | object | 对象，见 §5.3 | TLS 配置（出站 TLS，见 §5.3）。 |

通用拨号字段见 §5.2。

### `selector` — 手动选择器：在成员出站中选一个，可通过 API/Clash API 切换。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `outbounds` | array<string> | 数组 | 成员出站 tag 列表。 |
| `default` | string | — | 默认选中的成员 tag。 （按 tag 引用） |
| `interrupt_exist_connections` | boolean | `true` / `false` | 切换成员时中断已有连接。 |

通用拨号字段见 §5.2。

`outbounds` 必填，元素是其它出站的 tag；`default` 仅 selector 使用；`interrupt_exist_connections` 决定切换时是否断开已有连接。

### `shadowsocks` — Shadowsocks 客户端：AEAD/2022 方法、插件、多路复用。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`server`** | string | — | 服务器地址。 |
| **`server_port`** | integer（0–65535） | 整数 | 服务器端口。 |
| `method` | string | `none`, `aes-128-gcm`, `aes-192-gcm`, `aes-256-gcm`, `chacha20-ietf-poly1305`, `xchacha20-ietf-poly1305`, `2022-blake3-aes-128-gcm`, `2022-blake3-aes-256-gcm`, `2022-blake3-chacha20-poly1305`, `aes-128-ctr`, `aes-192-ctr`, `aes-256-ctr` …（共 18 项，见 §12） | 加密方法。2022 系列要求 base64 PSK；`none` 表示不加密。 |
| **`password`** | string | — | Shadowsocks 密码。 |
| `plugin` | string | — | Shadowsocks 插件（如 `obfs-local`、`v2ray-plugin`）。 |
| `plugin_opts` | string | — | 插件参数（分号分隔的 `key=value`）。 |
| `network` | string 或 array<string> | 可单值或数组：`tcp` / `udp` | 限制使用的网络：`tcp` / `udp`（可数组）。 |
| `udp_over_tcp` | boolean 或 object | `true` / `false`，或 `{ enabled, version }` | UDP over TCP 配置。 参阅 UDP Over TCP。 与 `multiplex` 冲突。 |
| `multiplex` | object | 对象，见 §5.4 | 出站多路复用（见 §5.4）。 |

通用拨号字段见 §5.2。

### `shadowtls` — ShadowTLS 客户端。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`server`** | string | — | 服务器地址。 |
| **`server_port`** | integer（0–65535） | 整数 | 服务器端口。 |
| `version` | integer | `1` / `2` / `3` | ShadowTLS 协议版本。 |
| `password` | string | — | 设置密码。 仅在 ShadowTLS v2/v3 协议中可用。 |
| `tls` | object | 对象，见 §5.3 | TLS 配置（出站 TLS，见 §5.3）。 |

通用拨号字段见 §5.2。

### `snell` — Snell v4/v6 客户端，必须显式指定 `version`。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`version`** | integer | `4` / `6` | Snell 协议版本，`4` `6` 之一。 版本 `4` 支持 HTTP 混淆（`obfs_mode` / `obfs_host`）；版本 `6` 以流量整形（`mode`） 取而代之，并要求 `psk` 长度为 12 到 255 字节。 Note 由于我们有意不支持 Snell v5 的 QUIC 代理模式，v5 的线路协议实际上与 v4 没有区别， 因此不提供独立的 v4 服务器和 v5 客户端。 |
| **`server`** | string | — | 服务器地址。 |
| **`server_port`** | integer（0–65535） | 整数 | 服务器端口。 |
| **`psk`** | string | — | 预共享密钥。 |
| `userkey` | string | — | 用户密钥，用于向多用户服务器进行认证。 |
| `reuse` | boolean | `true` / `false` | 启用连接复用（Snell v2 `CONNECT` 命令）。 |
| `network` | string 或 array<string> | 可单值或数组：`tcp` / `udp` | 限制使用的网络：`tcp` / `udp`（可数组）。 |
| `obfs_mode` | string | `none` / `http` / `tls` | 仅版本 4 HTTP 混淆模式，`none` `http` 之一。 默认为 `none`。 |
| `obfs_host` | string | — | 仅版本 4 `obfs_mode` 为 `http` 时发送的 HTTP `Host` 头。 默认为 `bing.com`。 |
| `mode` | string | `default` / `unshaped` / `unsafe-raw` | 仅版本 6 流量整形模式，`default` `unshaped` `unsafe-raw` 之一。 默认为 `default`。 |

通用拨号字段见 §5.2。 必须同时给出 `version`。

### `socks` — SOCKS4/4a/5 客户端。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`server`** | string | — | 服务器地址。 |
| **`server_port`** | integer（0–65535） | 整数 | 服务器端口。 |
| `version` | string | `4` / `4a` / `5` | SOCKS 版本, 可为 `4` `4a` `5`. 默认使用 SOCKS5。 |
| `username` | string | — | SOCKS 用户名。 |
| `password` | string | — | SOCKS5 密码。 |
| `network` | string 或 array<string> | 可单值或数组：`tcp` / `udp` | 限制使用的网络：`tcp` / `udp`（可数组）。 |
| `udp_over_tcp` | boolean 或 object | `true` / `false`，或 `{ enabled, version }` | UDP over TCP 配置。 参阅 UDP Over TCP。 |

通用拨号字段见 §5.2。

### `ssh` — SSH 隧道出站，内置 SSH 客户端。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`server`** | string | — | 服务器地址。 |
| `server_port` | integer（0–65535） | 整数 | 服务器端口，默认使用 22。 |
| `user` | string | — | SSH 用户, 默认使用 root。 |
| `password` | string | — | 密码。 |
| `private_key` | string 或 array<string> | — | 私钥（SSH 认证或 WireGuard 私钥）。 |
| `private_key_path` | string | — | 私钥文件路径。 |
| `private_key_passphrase` | string | — | 私钥口令。 |
| `host_key` | string 或 array<string> | — | SSH 主机密钥校验列表。 |
| `host_key_algorithms` | string 或 array<string> | — | 允许的 SSH 主机密钥算法。 |
| `client_version` | string | — | SSH 客户端版本字符串。 |
| `cipher` | string 或 array<string> | — | SSH 加密算法列表或单个值。 |
| `mac` | string 或 array<string> | — | SSH MAC 算法列表。 |
| `kex_algorithm` | string 或 array<string> | — | SSH 密钥交换算法列表。 |

通用拨号字段见 §5.2。

### `tor` — 调用外部 tor 可执行文件作为出站。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `executable_path` | string | — | tor 可执行文件路径。 |
| `extra_args` | array<string> | 数组 | 传给 tor 的额外参数。 |
| `data_directory` | string | — | tor 数据目录。 |
| `torrc` | object | 对象 | torrc 配置覆盖。 |

通用拨号字段见 §5.2。

`tor` 依赖系统安装 tor；`executable_path` 为空时在 `PATH` 中查找。

### `trojan` — Trojan 客户端：TLS、多路复用、传输层。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`server`** | string | — | 服务器地址。 |
| **`server_port`** | integer（0–65535） | 整数 | 服务器端口。 |
| **`password`** | string | — | Trojan 密码。 |
| `network` | string 或 array<string> | 可单值或数组：`tcp` / `udp` | 限制使用的网络：`tcp` / `udp`（可数组）。 |
| `tls` | object | 对象，见 §5.3 | TLS 配置（出站 TLS，见 §5.3）。 |
| `multiplex` | object | 对象，见 §5.4 | 出站多路复用（见 §5.4）。 |
| `transport` | object | 对象，见 §5.5 | V2Ray 传输层（见 §5.5）。 |

通用拨号字段见 §5.2。

### `tuic` — TUIC v5 QUIC 客户端。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`server`** | string | — | 服务器地址。 |
| **`server_port`** | integer（0–65535） | 整数 | 服务器端口。 |
| **`uuid`** | string | — | TUIC 用户 UUID |
| `password` | string | — | TUIC 用户密码 |
| `congestion_control` | string | `cubic` / `new_reno` / `bbr` | 拥塞控制：`cubic` / `new_reno` / `bbr`。 |
| `udp_relay_mode` | string | `native` / `quic` | TUIC UDP 中继模式：`native` / `quic`。 |
| `udp_over_stream` | boolean | `true` / `false` | TUIC 把 UDP 放到流上传输。 |
| `zero_rtt_handshake` | boolean | `true` / `false` | TUIC 0-RTT 握手。 |
| `heartbeat` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | TUIC 心跳间隔。 |
| `network` | string 或 array<string> | 可单值或数组：`tcp` / `udp` | 限制使用的网络：`tcp` / `udp`（可数组）。 |
| `tls` | object | 对象，见 §5.3 | TLS 配置（出站 TLS，见 §5.3）。 |
| `idle_timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 空闲超时。 |
| `keep_alive_period` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | QUIC 保活周期；默认由协议决定（通常 0/关闭）。 |
| `stream_receive_window` | integer 或 string | 整数或带单位字符串 | QUIC 单条流的接收窗口（字节数或带单位字符串）。 |
| `connection_receive_window` | integer 或 string | 整数或带单位字符串 | QUIC 连接级接收窗口。 |
| `max_concurrent_streams` | integer | 整数 | QUIC 允许的最大并发流数量。 |
| `initial_packet_size` | integer | 整数 | 初始 QUIC 数据包大小。 |
| `disable_path_mtu_discovery` | boolean | `true` / `false` | 禁用 QUIC 路径 MTU 发现。 |

通用拨号字段见 §5.2。

### `urltest` — 自动测速选择器：周期性探测成员延迟，自动选择最快者。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `outbounds` | array<string> | 数组 | 成员出站 tag 列表。 |
| `url` | string | — | 测速 URL。 |
| `interval` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 测速间隔。 |
| `tolerance` | integer（0–65535） | 整数 | 切换容差（毫秒）。 |
| `idle_timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 空闲超时。 |
| `interrupt_exist_connections` | boolean | `true` / `false` | 切换成员时中断已有连接。 |

通用拨号字段见 §5.2。

`outbounds` 必填，元素是其它出站的 tag；`default` 仅 selector 使用；`interrupt_exist_connections` 决定切换时是否断开已有连接。

### `vless` — VLESS 客户端：TLS/REALITY、传输层、多路复用。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`server`** | string | — | 服务器地址。 |
| **`server_port`** | integer（0–65535） | 整数 | 服务器端口。 |
| **`uuid`** | string | — | VLESS 用户 ID。 |
| `flow` | string | — | VLESS flow，如 `xtls-rprx-vision`。 |
| `network` | string 或 array<string> | 可单值或数组：`tcp` / `udp` | 限制使用的网络：`tcp` / `udp`（可数组）。 |
| `tls` | object | 对象，见 §5.3 | TLS 配置（出站 TLS，见 §5.3）。 |
| `multiplex` | object | 对象，见 §5.4 | 出站多路复用（见 §5.4）。 |
| `transport` | object | 对象，见 §5.5 | V2Ray 传输层（见 §5.5）。 |
| `packet_encoding` | string | — | UDP 包编码：`packetaddr` / `xudp`（VLESS/VMess）。 |

通用拨号字段见 §5.2。

### `vmess` — VMess 客户端。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`server`** | string | — | 服务器地址。 |
| **`server_port`** | integer（0–65535） | 整数 | 服务器端口。 |
| **`uuid`** | string | — | VMess 用户 ID。 |
| `security` | string | `auto` / `none` / `zero` / `aes-128-cfb` / `aes-128-gcm` / `chacha20-poly1305` | VMess 加密方式：`auto` / `none` / `zero` / `aes-128-gcm` / `chacha20-poly1305` 等。 |
| `alter_id` | integer | 整数 | VMess AlterID；`0` 表示 AEAD。 |
| `global_padding` | boolean | `true` / `false` | VMess 全局填充。 |
| `authenticated_length` | boolean | `true` / `false` | VMess 认证长度。 |
| `network` | string 或 array<string> | 可单值或数组：`tcp` / `udp` | 限制使用的网络：`tcp` / `udp`（可数组）。 |
| `tls` | object | 对象，见 §5.3 | TLS 配置（出站 TLS，见 §5.3）。 |
| `packet_encoding` | string | `packetaddr` / `xudp` | UDP 包编码：`packetaddr` / `xudp`（VLESS/VMess）。 |
| `multiplex` | object | 对象，见 §5.4 | 出站多路复用（见 §5.4）。 |
| `transport` | object | 对象，见 §5.5 | V2Ray 传输层（见 §5.5）。 |

通用拨号字段见 §5.2。

## 9. route — 路由

### 9.1 顶层字段

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `rules` | array<object> | 数组 | 路由规则列表（§9.2）。 |
| `rule_set` | array<object> | 数组 | 规则集定义（§9.4）。 |
| `final` | string | — | 未命中任何规则时使用的出站 tag；建议显式设置（Schema 不强制）。 （按 tag 引用） |
| `find_process` | boolean | `true` / `false` | 在没有 `process_name`、`process_path`、`package_name`、`user` 或 `user_id` 规则时启用进程搜索以输出日志。 |
| `find_neighbor` | boolean | `true` / `false` | 在没有 `source_mac_address` 或 `source_hostname` 规则时启用邻居解析以输出日志。 参阅 邻居解析 了解设置方法。（1.14.0+） |
| `dhcp_lease_files` | string 或 array<string> | — | 用于主机名和 MAC 地址解析的自定义 DHCP 租约文件路径。 为空时自动从常见 DHCP 服务器（dnsmasq、odhcpd、ISC dhcpd、Kea）检测。（1.14.0+） |
| `auto_detect_interface` | boolean | `true` / `false` | 默认将出站连接绑定到默认网卡，以防止在 tun 下出现路由环路。 如果设置了 `outbound.bind_interface` 设置，则不生效。 |
| `override_android_vpn` | boolean | `true` / `false` | 启用 `auto_detect_interface` 时接受 Android VPN 作为上游网卡。 |
| `default_interface` | string | — | 默认将出站连接绑定到指定网卡，以防止在 tun 下出现路由环路。 如果设置了 `auto_detect_interface` 设置，则不生效。 |
| `default_mark` | integer（0–4294967295） 或 string | 整数，或 `0x...` 十六进制字符串 | 默认为出站连接设置路由标记。 如果设置了 `outbound.routing_mark` 设置，则不生效。 |
| `default_domain_resolver` | string/object | DNS 服务器 tag，或 `{ server, strategy, ... }` 对象 | 详情参阅 拨号字段。 可以被 `outbound.domain_resolver` 覆盖。（1.12.0+） |
| `default_network_strategy` | string | `default` / `fallback` / `hybrid` | 所有未显式设置的拨号默认使用的网络策略。 |
| `default_network_type` | 枚举 或 array<枚举> | — | 详情参阅 拨号字段。（1.11.0+） |
| `default_fallback_network_type` | 枚举 或 array<枚举> | — | 详情参阅 拨号字段。（1.11.0+） |
| `default_fallback_delay` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 详情参阅 拨号字段。（1.11.0+） |
| `default_http_client` | string | — | 远程规则集使用的默认 HTTP 客户端 的标签。 如果为空且 `http_clients` 已定义，将使用第一个 HTTP 客户端。（1.14.0+） |

`auto_detect_interface` 让出站自动绑定到默认接口（桌面/路由器常用）；`default_domain_resolver` 是所有出站解析域名的默认 DNS；`find_process`/`find_neighbor` 开启进程/邻居信息匹配（部分平台需要特权）。

### 9.2 规则匹配字段

规则是「与」关系：同一字段的数组是「或」；`invert` 反转结果。`type` 默认 `default`；`type: logical` 用 `mode: and|or` + `rules` 组合子规则。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `inbound` | string 或 array<string> | — | 入站 标签。 |
| `ip_version` | integer | `4` / `6` | 4 或 6。 默认不限制。 |
| `network` | string 或 array<string> | 可单值或数组：`tcp` / `udp` / `icmp` | sing-box 1.13.0 中的更改 此类流量源自 `TUN`、`WireGuard` 和 `Tailscale` 入站，并可路由至 `Direct`、`WireGuard` 和 `Tailscale` 出站。 匹配网络类型。 `tcp`、`udp` 或 `icmp`。（1.13.0+） |
| `auth_user` | string 或 array<string> | — | 认证用户名，参阅入站设置。 |
| `protocol` | string 或 array<string> | 可单值或数组：`tls` / `http` / `quic` / `dns` / `stun` / `bittorrent` / `dtls` / `ssh` / `rdp` / `ntp` | 探测到的协议, 参阅 协议探测。 |
| `client` | string 或 array<string> | — | 探测到的客户端类型, 参阅 协议探测。（1.10.0+） |
| `domain` | string 或 array<string> | — | 匹配完整域名。 |
| `domain_suffix` | string 或 array<string> | — | 匹配域名后缀。 |
| `domain_keyword` | string 或 array<string> | — | 匹配域名关键字。 |
| `domain_regex` | string 或 array<string> | — | 匹配域名正则表达式。 |
| `source_ip_cidr` | string 或 array<string> | — | 匹配源 IP CIDR。 |
| `source_ip_is_private` | boolean | `true` / `false` | 匹配非公开源 IP。（1.8.0+） |
| `ip_cidr` | string 或 array<string> | — | 匹配 IP CIDR。 |
| `ip_is_private` | boolean | `true` / `false` | 匹配非公开 IP。（1.8.0+） |
| `source_port` | integer（0–65535） 或 array<integer（0–65535）> | — | 匹配源端口。 |
| `source_port_range` | string 或 array<string> | — | 匹配源端口范围。 |
| `port` | integer（0–65535） 或 array<integer（0–65535）> | — | 匹配端口。 |
| `port_range` | string 或 array<string> | — | 匹配端口范围。 |
| `process_name` | string 或 array<string> | — | 匹配进程名称。 |
| `process_path` | string 或 array<string> | — | 匹配进程路径。 |
| `process_path_regex` | string 或 array<string> | — | 使用正则表达式匹配进程路径。（1.10.0+） |
| `package_name` | string 或 array<string> | — | 匹配 Android 应用包名。 |
| `package_name_regex` | string 或 array<string> | — | 使用正则表达式匹配 Android 应用包名。（1.14.0+） |
| `user` | string 或 array<string> | — | 匹配用户名。 |
| `user_id` | integer 或 array<integer> | — | 匹配用户 ID。 |
| `clash_mode` | string | — | 匹配 Clash 模式。 |
| `network_type` | 枚举 或 array<枚举> | `cellular` / `ethernet` / `wifi` / `other`（可数组） | 仅在 Android 与 Apple 平台图形客户端中支持。 匹配网络类型。 可用值: `wifi`, `cellular`, `ethernet` and `other`.（1.11.0+） |
| `network_is_expensive` | boolean | `true` / `false` | 仅在 Android 与 Apple 平台图形客户端中支持。 匹配如果网络被视为计费 (在 Android) 或被视为昂贵， 像蜂窝网络或个人热点 (在 Apple 平台)。（1.11.0+） |
| `network_is_constrained` | boolean | `true` / `false` | 仅在 Apple 平台图形客户端中支持。 匹配如果网络在低数据模式下。（1.11.0+） |
| `wifi_ssid` | string 或 array<string> | — | 匹配 WiFi SSID。 参阅 Wi-Fi 状态。 |
| `wifi_bssid` | string 或 array<string> | — | 匹配 WiFi BSSID。 参阅 Wi-Fi 状态。 |
| `interface_address` | object | 对象 | 匹配接口地址。（1.13.0+） |
| `network_interface_address` | object | 对象 | 仅在 Android 与 Apple 平台图形客户端中支持。 匹配网络接口（可用值同 `network_type`）地址。（1.13.0+） |
| `default_interface_address` | string 或 array<string> | — | 匹配默认接口地址。（1.13.0+） |
| `source_mac_address` | string 或 array<string> | — | 匹配源设备 MAC 地址。（1.14.0+） |
| `source_hostname` | string 或 array<string> | — | 匹配源设备从 DHCP 租约获取的主机名。（1.14.0+） |
| `preferred_by` | string 或 array<string> | — | 匹配制定出站的首选路由。（1.13.0+） |
| `rule_set` | string 或 array<string> | — | 匹配规则集。（1.8.0+） |
| `rule_set_ip_cidr_match_source` | boolean | `true` / `false` | 使规则集中的 `ip_cidr` 规则匹配源 IP。（1.10.0+） |
| `invert` | boolean | `true` / `false` | 反选匹配结果。 |

逻辑规则字段：`type: logical`、`mode`（`and`/`or`）、`rules`（子规则数组）、`invert`。

### 9.3 规则动作

规则默认动作是 `route`；`action` 决定该规则命中后做什么。

#### `route` — 把连接路由到指定出站；最常用的动作，也是规则的默认动作。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`outbound`** | string | — | 目标出站的标签。 （按 tag 引用） |
| `override_address` | string | — | 覆盖目标地址。 |
| `override_port` | integer（0–65535） | 整数 | 覆盖目标端口。 |
| `network_strategy` | string | `default` / `fallback` / `hybrid` | 详情参阅 拨号字段。 仅当出站为 `direct` 且 `outbound.bind_interface`, `outbound.inet4_bind_address` 且 `outbound.inet6_bind_address` 未设置时生效。 |
| `fallback_delay` | integer（0–4294967295） | 整数 | 详情参阅 拨号字段。 |
| `udp_disable_domain_unmapping` | boolean | `true` / `false` | 如果启用，对于地址为域的 UDP 代理请求，将在响应中发送原始包地址而不是映射的域。 此选项用于兼容不支持接收带有域地址的 UDP 包的客户端，如 Surge。 |
| `udp_connect` | boolean | `true` / `false` | 如果启用，将尝试将 UDP 连接 connect 到目标而不是 listen。 |
| `udp_timeout` | 时长 | 整数（纳秒）或时长字符串 | UDP 连接超时时间。 设置比入站 UDP 超时更大的值将无效。 已探测协议连接的默认值： 如果没有探测到协议，以下端口将默认识别为协议： |
| `tls_fragment` | boolean | `true` / `false` | 通过分段 TLS 握手数据包来绕过防火墙检测。 此功能旨在规避基于明文数据包匹配的简单防火墙，不应该用于规避真的审查。 由于性能不佳，请首先尝试 `tls_record_fragment`，且仅应用于已知被阻止的服务器名称。 在 Linux、Apple 平台和需要管理员权限的 Windows 系统上，可自动检测等待时间。 若无法自动检测，将回退使用 `tls_fragment_fallback_delay` 指定的固定等待时间。 此…（1.12.0+） |
| `tls_fragment_fallback_delay` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 当 TLS 分片功能无法自动判定等待时间时使用的回退值。 默认使用 `500ms`。（1.12.0+） |
| `tls_record_fragment` | boolean | `true` / `false` | 通过分段 TLS 握手数据包到多个 TLS 记录来绕过防火墙检测。（1.12.0+） |
| `tls_spoof` | string | — | 在真实 ClientHello 之前注入携带本字段所指定 SNI 的伪造 TLS ClientHello， 用于欺骗仅放行特定主机名的 SNI 过滤中间盒。 详情与所需权限参阅出站 TLS `spoof`。（1.14.0+） |
| `tls_spoof_method` | string | `wrong-sequence` / `wrong-checksum` / `wrong-ack` / `wrong-md5` / `wrong-timestamp` | 控制伪造报文被真实服务器拒绝的方式。完整取值表与平台说明参阅出站 TLS `spoof_method`。（1.14.0+） |

#### `route-options` — 只设置覆盖地址/端口、UDP、TLS 分片等连接选项，不改变出站。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `override_address` | string | — | 覆盖目标地址。 |
| `override_port` | integer（0–65535） | 整数 | 覆盖目标端口。 |
| `network_strategy` | string | `default` / `fallback` / `hybrid` | 详情参阅 拨号字段。 仅当出站为 `direct` 且 `outbound.bind_interface`, `outbound.inet4_bind_address` 且 `outbound.inet6_bind_address` 未设置时生效。 |
| `fallback_delay` | integer（0–4294967295） | 整数 | 详情参阅 拨号字段。 |
| `udp_disable_domain_unmapping` | boolean | `true` / `false` | 如果启用，对于地址为域的 UDP 代理请求，将在响应中发送原始包地址而不是映射的域。 此选项用于兼容不支持接收带有域地址的 UDP 包的客户端，如 Surge。 |
| `udp_connect` | boolean | `true` / `false` | 如果启用，将尝试将 UDP 连接 connect 到目标而不是 listen。 |
| `udp_timeout` | 时长 | 整数（纳秒）或时长字符串 | UDP 连接超时时间。 设置比入站 UDP 超时更大的值将无效。 已探测协议连接的默认值： 如果没有探测到协议，以下端口将默认识别为协议： |
| `tls_fragment` | boolean | `true` / `false` | 通过分段 TLS 握手数据包来绕过防火墙检测。 此功能旨在规避基于明文数据包匹配的简单防火墙，不应该用于规避真的审查。 由于性能不佳，请首先尝试 `tls_record_fragment`，且仅应用于已知被阻止的服务器名称。 在 Linux、Apple 平台和需要管理员权限的 Windows 系统上，可自动检测等待时间。 若无法自动检测，将回退使用 `tls_fragment_fallback_delay` 指定的固定等待时间。 此…（1.12.0+） |
| `tls_fragment_fallback_delay` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 当 TLS 分片功能无法自动判定等待时间时使用的回退值。 默认使用 `500ms`。（1.12.0+） |
| `tls_record_fragment` | boolean | `true` / `false` | 通过分段 TLS 握手数据包到多个 TLS 记录来绕过防火墙检测。（1.12.0+） |
| `tls_spoof` | string | — | 在真实 ClientHello 之前注入携带本字段所指定 SNI 的伪造 TLS ClientHello， 用于欺骗仅放行特定主机名的 SNI 过滤中间盒。 详情与所需权限参阅出站 TLS `spoof`。（1.14.0+） |
| `tls_spoof_method` | string | `wrong-sequence` / `wrong-checksum` / `wrong-ack` / `wrong-md5` / `wrong-timestamp` | 控制伪造报文被真实服务器拒绝的方式。完整取值表与平台说明参阅出站 TLS `spoof_method`。（1.14.0+） |

#### `bypass` — 绕过 sing-box，把连接交还内核/原网络栈（平台支持时）。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`outbound`** | string | — | 目标出站的标签。 （按 tag 引用） |
| `override_address` | string | — | 覆盖目标地址。 |
| `override_port` | integer（0–65535） | 整数 | 覆盖目标端口。 |
| `network_strategy` | string | `default` / `fallback` / `hybrid` | 详情参阅 拨号字段。 仅当出站为 `direct` 且 `outbound.bind_interface`, `outbound.inet4_bind_address` 且 `outbound.inet6_bind_address` 未设置时生效。 |
| `fallback_delay` | integer（0–4294967295） | 整数 | 详情参阅 拨号字段。 |
| `udp_disable_domain_unmapping` | boolean | `true` / `false` | 如果启用，对于地址为域的 UDP 代理请求，将在响应中发送原始包地址而不是映射的域。 此选项用于兼容不支持接收带有域地址的 UDP 包的客户端，如 Surge。 |
| `udp_connect` | boolean | `true` / `false` | 如果启用，将尝试将 UDP 连接 connect 到目标而不是 listen。 |
| `udp_timeout` | 时长 | 整数（纳秒）或时长字符串 | UDP 连接超时时间。 设置比入站 UDP 超时更大的值将无效。 已探测协议连接的默认值： 如果没有探测到协议，以下端口将默认识别为协议： |
| `tls_fragment` | boolean | `true` / `false` | 通过分段 TLS 握手数据包来绕过防火墙检测。 此功能旨在规避基于明文数据包匹配的简单防火墙，不应该用于规避真的审查。 由于性能不佳，请首先尝试 `tls_record_fragment`，且仅应用于已知被阻止的服务器名称。 在 Linux、Apple 平台和需要管理员权限的 Windows 系统上，可自动检测等待时间。 若无法自动检测，将回退使用 `tls_fragment_fallback_delay` 指定的固定等待时间。 此…（1.12.0+） |
| `tls_fragment_fallback_delay` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 当 TLS 分片功能无法自动判定等待时间时使用的回退值。 默认使用 `500ms`。（1.12.0+） |
| `tls_record_fragment` | boolean | `true` / `false` | 通过分段 TLS 握手数据包到多个 TLS 记录来绕过防火墙检测。（1.12.0+） |
| `tls_spoof` | string | — | 在真实 ClientHello 之前注入携带本字段所指定 SNI 的伪造 TLS ClientHello， 用于欺骗仅放行特定主机名的 SNI 过滤中间盒。 详情与所需权限参阅出站 TLS `spoof`。（1.14.0+） |
| `tls_spoof_method` | string | `wrong-sequence` / `wrong-checksum` / `wrong-ack` / `wrong-md5` / `wrong-timestamp` | 控制伪造报文被真实服务器拒绝的方式。完整取值表与平台说明参阅出站 TLS `spoof_method`。（1.14.0+） |

#### `reject` — 拒绝连接：可静默丢弃或回复指定错误。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `method` | string | `(空)` / `default` / `drop` / `reply` | 对于 TCP 和 UDP 连接：`default`: 对于 TCP 连接回复 RST，对于 UDP 包回复 ICMP 端口不可达。、`drop`: 丢弃数据包。 对于 ICMP 回显请求：`default`: 回复 ICMP 主机不可达。、`drop`: 丢弃数据包。、`reply`: 回复以 ICMP 回显应答。 |
| `no_drop` | boolean | `true` / `false` | 如果未启用，则 30 秒内触发 50 次后，`method` 将被暂时覆盖为 `drop`。 当 `method` 设为 `drop` 时不可用。 |

#### `hijack-dns` — 劫持 DNS 查询，交给内部 DNS 模块处理。

_没有额外字段；按对象类型使用 §5.1 监听字段或 §5.2 拨号字段。_

#### `sniff` — 协议探测：从连接首包提取 SNI/Host/协议，供后续规则使用。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `sniffer` | string 或 array<string> | 可单值或数组：`tls` / `http` / `quic` / `dns` / `stun` / `bittorrent` / `dtls` / `ssh` / `rdp` / `ntp` | 启用的探测器。 默认启用所有探测器。 可用的协议值可以在 协议嗅探 中找到。 |
| `timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 探测超时时间。 默认使用 300ms。 |

#### `resolve` — 在路由阶段把域名解析成 IP，供后续 IP 规则匹配。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `server` | string | — | 指定要使用的 DNS 服务器的标签，而不是通过 DNS 路由进行选择。 （按 tag 引用） |
| `timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 探测超时时间。 默认使用 300ms。 |
| `strategy` | 枚举 | `as_is` / `prefer_ipv4` / `prefer_ipv6` / `ipv4_only` / `ipv6_only` | DNS 解析策略，可用值有：`prefer_ipv4`、`prefer_ipv6`、`ipv4_only`、`ipv6_only`。 默认使用 `dns.strategy`。 |
| `disable_cache` | boolean | `true` / `false` | 在此查询中禁用缓存。（1.12.0+） |
| `disable_optimistic_cache` | boolean | `true` / `false` | 在此查询中禁用乐观 DNS 缓存。（1.14.0+） |
| `rewrite_ttl` | integer（0–4294967295） | 整数 | 重写 DNS 回应中的 TTL。（1.12.0+） |
| `client_subnet` | string | — | 默认情况下，将带有指定 IP 前缀的 `edns0-subnet` OPT 附加记录附加到每个查询。 如果值是 IP 地址而不是前缀，则会自动附加 `/32` 或 `/128`。 将覆盖 `dns.client_subnet`.（1.12.0+） |

### 9.4 规则集 rule_set

`route.rule_set[]` 定义可复用的规则集，规则里用 `rule_set: ["tag", ...]` 引用。

| 类型 | 形态 | 字段 | 说明 |
|---|---|---|---|
| `type: inline` | object | `tag`、`rules`（无头规则数组） | 直接内联规则。 |
| `type: local` | object | `tag`、`format`（`source`/`binary`）、`path` | 本地文件；`.srs` 用 `binary`，JSON 用 `source`。 |
| `type: remote` | object | `tag`、`format`、`url`、`initial_path`、`http_client`、`update_interval` | 远程下载并缓存。 |

无头规则（HeadlessRule）支持 `domain`/`domain_suffix`/`domain_keyword`/`domain_regex`、`ip_cidr`、`source_ip_cidr`、`port`/`port_range`、`query_type` 等匹配字段；`rule_set_ip_cidr_match_source` 让 IP 规则匹配源地址而非目标。

## 10. services — 内置服务

service 是 sing-box 进程内提供的附加服务，不是代理出入口；大多数需要监听字段。

| type | 作用 |
|---|---|
| `api` | sing-box API（gRPC + gRPC-Web），供图形客户端或 dashboard 观察/控制实例，可选内置 dashboard。 |
| `derp` | Tailscale DERP 中继服务器（类似 derper），可组成 mesh。 |
| `resolved` | 伪造的 systemd-resolved DBus 服务，从 NetworkManager 等接收 DNS 设置。 |
| `ssm-api` | Shadowsocks 服务器管理 API（SSM v1）。 |
| `ccm` | Claude Code 多路复用器：本地完成 Anthropic OAuth，远程用自定义令牌访问。 |
| `ocm` | OpenAI Codex 多路复用器：本地完成 OpenAI OAuth，远程用自定义令牌访问。 |
| `hysteria-realm` | Hysteria2 NAT 穿透会合服务；NAT 后的服务端向 realm 注册，客户端经 realm 连接。 |
| `usbip-server` | USB/IP 服务端：导出本机 USB 设备。 |
| `usbip-client` | USB/IP 客户端：导入远端导出的 USB 设备。 |
| `oom-killer` | 内存压力守护：超过阈值时终止占用最高的连接/会话（1.14 新增）。 |

### `api` — sing-box API（gRPC + gRPC-Web），供图形客户端或 dashboard 观察/控制实例，可选内置 dashboard。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `secret` | string | — | API 密钥。 客户端通过标准的 `authorization: Bearer <secret>` gRPC metadata 头认证。 默认无需认证。 |
| `access_control_allow_origin` | string 或 array<string> | — | 允许的 CORS 来源,默认使用 `*`。 |
| `access_control_allow_private_network` | boolean | `true` / `false` | 允许从私有网络访问。 |
| `dashboard` | boolean 或 string 或 object | `true` / `false`、目录路径，或 `{ enabled, path }` | 下载并通过 API 监听器在 `/dashboard/` 提供的 Web 仪表板；其他浏览器请求将被重定向到该路径。 该对象可以替换为布尔值（等同于 `{ "enabled": <bool> }`）， 或字符串路径（等同于 `{ "enabled": true, "path": "<string>" }`）。 enabled 启用仪表板。 path 存放仪表板文件的目录。 默认使用工作目录下的 `dashboard`。 如果目录中包… |
| `tls` | object | 对象，见 §5.3 | TLS 配置,参阅 TLS。 |

监听字段见 §5.1；TLS 见 §5.3。

### `derp` — Tailscale DERP 中继服务器（类似 derper），可组成 mesh。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `tls` | object | 对象，见 §5.3 | TLS 配置，参阅 TLS。 |
| **`config_path`** | string | — | Derper 配置文件路径。 示例：`derper.key` |
| `verify_client_endpoint` | string 或 array<string> | — | 用于验证客户端的 Tailscale 端点标签。 |
| `verify_client_url` | string 或 object 或 array<string 或 object> | — | 用于验证客户端的 URL。 对象格式： 将数组值设置为字符串 `__URL__` 等同于配置： |
| `home` | string | — | 在根路径提供的内容。可以留空（默认值，显示默认主页）、`blank` 显示空白页面，或一个重定向的 URL。 |
| `mesh_with` | object 或 array<object> | — | 与其他 DERP 服务器组网。 对象格式： 对象字段：`server`：必填 DERP 服务器地址。、`server_port`：必填 DERP 服务器端口。、`host`：自定义 DERP 主机名。、`tls`：TLS、`拨号字段`：拨号字段 |
| `mesh_psk` | string | — | DERP 组网的预共享密钥。 |
| `mesh_psk_file` | string | — | DERP 组网的预共享密钥文件。 |
| `stun` | integer（0–65535） 或 object | — | STUN 服务器监听选项。 对象格式： 对象字段：`enabled`：必填 启用 STUN 服务器。、`listen`：必填 STUN 服务器监听地址，默认为 `::`。、`listen_port`：必填 STUN 服务器监听端口，默认为 `3478`。、`其他监听字段`：监听字段 将 `stun` 值设置为数字 `__PORT__` 等同于配置： |

监听字段见 §5.1；TLS 见 §5.3。

### `resolved` — 伪造的 systemd-resolved DBus 服务，从 NetworkManager 等接收 DNS 设置。

_没有额外字段；按对象类型使用 §5.1 监听字段或 §5.2 拨号字段。_

监听字段见 §5.1。

### `ssm-api` — Shadowsocks 服务器管理 API（SSM v1）。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`servers`** | object | 对象 | 从 HTTP 端点到 Shadowsocks 入站 标签的映射对象。 选定的 Shadowsocks 入站必须配置启用 managed。 示例： |
| `cache_path` | string | — | 如果设置，当服务器即将停止时，流量和用户状态将保存到指定的 JSON 文件中， 以便在下次启动时恢复。 |
| `tls` | object | 对象，见 §5.3 | TLS 配置，参阅 TLS。 |

监听字段见 §5.1；TLS 见 §5.3。

### `ccm` — Claude Code 多路复用器：本地完成 Anthropic OAuth，远程用自定义令牌访问。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `tls` | object | 对象，见 §5.3 | TLS 配置，参阅 TLS。 |
| `credential_path` | string | — | Claude Code OAuth 凭据文件的路径。 如果未指定，默认值为：如果设置了 `CLAUDE_CONFIG_DIR` 环境变量，则使用 `$CLAUDE_CONFIG_DIR/.credentials.json`；否则使用 `~/.claude/.credentials.json` 在 macOS 上，首先从系统钥匙串读取凭据，如果不可用则回退到文件。 刷新的令牌会自动写回相同位置。 |
| `users` | array<object> | 数组，元素见 §5.7 | 用于令牌身份验证的授权用户列表。 如果为空，则不需要身份验证。 对象格式： 对象字段：`name`：用于跟踪的用户名标识符。、`token`：用于身份验证的 Bearer 令牌。Claude Code 通过设置 `ANTHROPIC_AUTH_TOKEN` 环境变量为其令牌值进行身份验证。 |
| `headers` | object | 键值对（值可为字符串或数组） | 发送到 Claude API 的自定义 HTTP 头。 这些头会覆盖同名的现有头。 |
| `usages_path` | string | — | 用于存储聚合 API 使用统计信息的文件路径。 如果未指定，使用跟踪将被禁用。 启用后，服务会跟踪并保存全面的统计信息，包括：请求计数；令牌使用量（输入、输出、缓存读取、缓存创建）；基于 Claude API 定价计算的美元成本 统计信息按模型、上下文窗口（200k 标准版 vs 1M 高级版）以及可选的用户（启用身份验证时）进行组织。 统计文件每分钟自动保存一次，并在服务关闭时保存。 |

监听字段见 §5.1；TLS 见 §5.3。

`users[]` 元素为 `{ name, token }`，`token` 是远程客户端使用的 Bearer 令牌；为空表示不认证。

### `ocm` — OpenAI Codex 多路复用器：本地完成 OpenAI OAuth，远程用自定义令牌访问。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `tls` | object | 对象，见 §5.3 | TLS 配置，参阅 TLS。 |
| `credential_path` | string | — | OpenAI OAuth 凭据文件的路径。 如果未指定，默认值为：如果设置了 `CODEX_HOME` 环境变量，则使用 `$CODEX_HOME/auth.json`；否则使用 `~/.codex/auth.json` 刷新的令牌会自动写回相同位置。 |
| `users` | array<object> | 数组，元素见 §5.7 | 用于令牌身份验证的授权用户列表。 如果为空，则不需要身份验证。 对象格式： 对象字段：`name`：用于跟踪的用户名标识符。、`token`：用于身份验证的 Bearer 令牌。客户端通过设置 `Authorization: Bearer <token>` 头进行身份验证。 |
| `headers` | object | 键值对（值可为字符串或数组） | 发送到 OpenAI API 的自定义 HTTP 头。 这些头会覆盖同名的现有头。 |
| `usages_path` | string | — | 用于存储聚合 API 使用统计信息的文件路径。 如果未指定，使用跟踪将被禁用。 启用后，服务会跟踪并保存全面的统计信息，包括：请求计数；令牌使用量（输入、输出、缓存）；基于 OpenAI API 定价计算的美元成本 统计信息按模型以及可选的用户（启用身份验证时）进行组织。 统计文件每分钟自动保存一次，并在服务关闭时保存。 |

监听字段见 §5.1；TLS 见 §5.3。

`users[]` 元素为 `{ name, token }`，`token` 是远程客户端使用的 Bearer 令牌；为空表示不认证。

### `hysteria-realm` — Hysteria2 NAT 穿透会合服务；NAT 后的服务端向 realm 注册，客户端经 realm 连接。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `tls` | object | 对象，见 §5.3 | TLS 配置，参阅 TLS。 配置后，realm 将通过 TLS 提供 HTTP/2 服务；否则提供明文 HTTP/1.1。 |
| `idle_timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 空闲连接超时；不同组件含义略有差异（HTTP2 中为 GOAWAY/PING 健康检查）。 |
| `keep_alive_period` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | QUIC 保活周期；默认由协议决定（通常 0/关闭）。 |
| `stream_receive_window` | integer 或 string | 整数或带单位字符串 | QUIC 单条流的接收窗口（字节数或带单位字符串）。 |
| `connection_receive_window` | integer 或 string | 整数或带单位字符串 | QUIC 连接级接收窗口。 |
| `max_concurrent_streams` | integer | 整数 | QUIC 允许的最大并发流数量。 |
| **`users`** | array<object> | 数组，元素见 §5.7 | 授权用户。 |

监听字段见 §5.1；TLS 见 §5.3。

### `usbip-server` — USB/IP 服务端：导出本机 USB 设备。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `provider` | string（固定） | 固定 `dynamic` | 设备来源提供者。、`default`：导出由 `devices` 匹配的本地设备。默认值。、`dynamic`：设备在运行时通过 sing-box API 客户端提供，而非来自配置文件，支持的平台包括 macOS 和 Android 上的 sing-box 图形客户端，以及配合 sing-box Dashboard 的基于 Chromium 的浏览器。 `default` 提供者仅支持通过 CLI 直接运行在 Linux、Windo… |
| `devices` | array<object> | 数组 | 使用 `default` 提供者时 必填。 设备匹配列表，用于选择要导出的本地 USB 设备。 对象格式： 对象字段：`bus_id`：USB 总线 ID，例如 `1-2`。、`vendor_id`：USB 供应商 ID，为数字。、`product_id`：USB 产品 ID，为数字。、`serial`：设备序列号。 在一个对象内，所有指定的字段都必须匹配；多个对象之间取并集。至少需要一个字段。 |

监听字段见 §5.1。

### `usbip-client` — USB/IP 客户端：导入远端导出的 USB 设备。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| **`server`** | string | — | 远程 `usbip-server` 地址。 |
| `server_port` | integer（0–65535） | 整数 | 远程 `usbip-server` 端口。默认为 `3240`。 |
| `devices` | array<object> | 数组 | 设备匹配列表，用于选择要导入的远程设备。如果为空，则导入所有已导出的设备。 对象格式： 对象字段：`bus_id`：USB 总线 ID，例如 `1-2`。、`vendor_id`：USB 供应商 ID，为数字。、`product_id`：USB 产品 ID，为数字。、`serial`：设备序列号。 在一个对象内，所有指定的字段都必须匹配；多个对象之间取并集。至少需要一个字段。 |

### `oom-killer` — 内存压力守护：超过阈值时终止占用最高的连接/会话（1.14 新增）。

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `memory_limit` | integer 或 string | — | 内存上限（字节，或带单位字符串）。 |
| `safety_margin` | integer 或 string | — | 触发回收前保留的安全余量。 |
| `min_interval` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 两次检查之间的最小间隔。 |
| `max_interval` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 两次检查之间的最大间隔。 |

该服务在 1.14 引入，文档尚未收录；字段含义：`memory_limit` 内存上限（字节或带单位字符串）、`safety_margin` 安全余量、`min_interval`/`max_interval` 两次检查的最小/最大间隔。

## 11. experimental — 实验性功能

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `cache_file` | object |  | 持久化缓存（含 DNS/FakeIP/规则集等）。 |
| `clash_api` | object |  | Clash 兼容 API/面板。 |
| `v2ray_api` | object |  | V2Ray 统计 API。 |
| `debug` | object |  | Go 运行时调试与内存限制。 |

### 11.1 cache_file

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `enabled` | boolean | `true` / `false` | 启用缓存文件。 |
| `path` | string | 文件路径（部分字段可为数组） | 缓存文件路径，默认使用`cache.db`。 |
| `cache_id` | string | — | 缓存文件中的标识符。 如果不为空，配置特定的数据将使用由其键控的单独存储。 |
| `store_fakeip` | boolean | `true` / `false` | 将 fakeip 存储在缓存文件中。 |
| `rdrc_timeout` | 时长 | Go 时长字符串，如 `30s`、`1m30s`；也可用纯数字（纳秒） | 被拒绝的 DNS 响应的缓存时长，默认 `7d`（1.14.4 可用；1.16 起移除）。 |
| `store_dns` | boolean | `true` / `false` | 将 DNS 缓存存储在缓存文件中。（1.14.0+） |

### 11.2 clash_api

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `external_controller` | string | — | RESTful web API 监听地址。如果为空，则禁用 Clash API。 |
| `external_ui` | string | — | 到静态网页资源目录的相对路径或绝对路径。sing-box 会在 `http://{{external-controller}}/ui` 下提供它。 |
| `external_ui_download_url` | string | — | 静态网页资源的 ZIP 下载 URL，如果指定的 `external_ui` 目录为空，将使用。 默认使用 `https://github.com/MetaCubeX/Yacd-meta/archive/gh-pages.zip`。 |
| `external_ui_download_detour` | string | — | 用于下载静态网页资源的出站的标签。 如果为空，将使用默认出站。 （按 tag 引用） |
| `secret` | string | — | RESTful API 的密钥（可选） 通过指定 HTTP 标头 `Authorization: Bearer ${secret}` 进行身份验证 如果 RESTful API 正在监听 0.0.0.0，请始终设置一个密钥。 |
| `default_mode` | string | — | Clash 中的默认模式，默认使用 `Rule`。 此设置没有直接影响，但可以通过 `clash_mode` 规则项在路由和 DNS 规则中使用。 |
| `access_control_allow_origin` | string 或 array<string> | — | 允许的 CORS 来源，默认使用 `*`。 要从公共网站访问私有网络上的 Clash API，必须在 `access_control_allow_origin` 中明确指定它而不是使用 `*`。（1.10.0+） |
| `access_control_allow_private_network` | boolean | `true` / `false` | 允许从私有网络访问。 要从公共网站访问私有网络上的 Clash API，必须启用 `access_control_allow_private_network`。（1.10.0+） |

`external_controller` 形如 `127.0.0.1:9090`；`external_ui` 指向面板目录；`secret` 是 API 密码；`default_mode` 是初始模式（`rule`/`global`/`direct`）。

### 11.3 v2ray_api

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `listen` | string | — | gRPC API 监听地址。如果为空，则禁用 V2Ray API。 |
| `stats` | object | 对象 | 流量统计服务设置。 |

`listen` 为 gRPC 监听地址。`stats` 子对象：

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `enabled` | boolean | `true` / `false` | 启用流量统计。 |
| `inbounds` | boolean | `true` / `false` | 按入站统计。 |
| `outbounds` | boolean | `true` / `false` | 按出站统计。 |
| `users` | boolean | `true` / `false` | 按用户统计。 |

### 11.4 debug

| 字段 | 类型 | 取值 / 默认 | 说明 |
|---|---|---|---|
| `listen` | string | — | 监听地址；不填通常表示所有地址。 |
| `gc_percent` | integer | 整数 | Go GC 触发百分比（`GOGC`）。 |
| `max_stack` | integer | 整数 | Go 协程栈上限（字节）。 |
| `max_threads` | integer | 整数 | Go 运行时最大线程数。 |
| `panic_on_fault` | boolean | `true` / `false` | 发生故障时直接 panic，便于抓取现场。 |
| `trace_back` | string | — | 崩溃时输出的堆栈回溯文件路径。 |
| `memory_limit` | integer 或 string | — | 内存上限（字节，或带单位字符串）。 |
| `oom_killer` | boolean | `true` / `false` | 启用 OOM 处理：内存超限时终止占用最高的连接。 |

`memory_limit` 限制 Go 堆内存（字节或带单位字符串）；`oom_killer` 在超限时触发 OOM 处理；`gc_percent`、`max_stack`、`max_threads`、`panic_on_fault`、`trace_back` 是 Go 运行时/崩溃调试参数。

## 12. 枚举速查

以下是配置中最常打交道的枚举；协议列表（inbound/outbound/dns/endpoint/service 的 `type`）见各章总表。

| 枚举 | 取值 | 作用 |
|---|---|---|
| 日志级别 | `trace` / `debug` / `info` / `warn` / `warning` / `error` / `fatal` / `panic` | 越往后越严重；`warning` 是 `warn` 的别名。 |
| 域名策略 | `as_is` / `prefer_ipv4` / `prefer_ipv6` / `ipv4_only` / `ipv6_only` | 控制解析结果优先族；空串跟随默认。 |
| 网络策略 | `default` / `fallback` / `hybrid` | 多网络下的拨号策略。 |
| 网络类型 | `cellular` / `ethernet` / `wifi` / `other` | 限定/回退拨号网络。 |
| 规则网络 | `tcp` / `udp` / `icmp` | 路由规则 `network`；DNS 规则只有 `tcp`/`udp`。 |
| IP 版本 | `4` / `6` | `ip_version`。 |
| 嗅探协议 | `tls` / `http` / `quic` / `dns` / `stun` / `bittorrent` / `dtls` / `ssh` / `rdp` / `ntp` | `sniff` 动作与 `protocol` 匹配字段。 |
| 拒绝方式 | `default` / `drop` / `reply` | `reject.method`；空值等同 default。 |
| Shadowsocks 方法（入站） | `none` / `aes-128-gcm` / `aes-192-gcm` / `aes-256-gcm` / `chacha20-ietf-poly1305` / `xchacha20-ietf-poly1305` / `2022-blake3-*` | `2022-*` 需要 base64 PSK。 |
| VMess 加密 | `auto` / `none` / `zero` / `aes-128-cfb` / `aes-128-gcm` / `chacha20-poly1305` | 出站 `security`。 |
| SOCKS 版本 | `4` / `4a` / `5` | 出站 `version`。 |
| 拥塞控制 | `cubic` / `new_reno` / `bbr` | TUIC/Hysteria2。 |
| BBR 配置 | `standard` / `conservative` / `aggressive` | Hysteria2 `bbr_profile`。 |
| TLS 版本 | `1.0` / `1.1` / `1.2` / `1.3` | `min_version`/`max_version`。 |
| 客户端证书验证 | `no` / `request` / `require-any` / `verify-if-given` / `require-and-verify` | 入站 TLS `client_authentication`。 |
| Clash 模式 | `rule` / `global` / `direct` | `clash_api.default_mode`。 |

## 13. 版本变化与已移除项

这份 Schema 对应 1.14.4。升级旧配置时，以下字段已不存在，写入会直接报 “unknown field”：

| 已移除 / 废弃项 | 替代方式 |
|---|---|
| `inbounds[].sniff` / `sniff_override_destination` / `sniff_timeout` | 1.11 废弃、1.13 移除；改由路由 `action: sniff` 完成 |
| `inbounds[].domain_strategy` | 1.11 废弃、1.13 移除；改用 DNS 规则/`domain_resolver` |
| `inbounds[].udp_disable_domain_unmapping` | 1.11 废弃、1.13 移除；改用路由 `route-options` 的同名字段 |
| `outbounds[].type: wireguard` | 1.13 移除，改用 `endpoints[].type=wireguard` |
| `outbounds[].type: dns` | 1.13 移除，改用内部 DNS 或 `direct` |
| DNS 服务器 `type: legacy` | 1.14 移除，改用 `local`/`udp` 等新格式 |
| 规则字段 `geosite` / `geoip` | 已移除，改用 `rule_set` 引用 `.srs` |

1.14 引入/值得注意的能力：`http_clients`、`network_namespaces`、`certificate_providers`、`endpoints`（OpenVPN/OpenConnect）、`services`（api/hysteria-realm/usbip/oom-killer，ccm/ocm 自 1.13）、`snell`、`cloudflared`、TUN 的 `dns_mode`/`include_mac_address`、DNS 的 `evaluate`/`respond`/`predefined` 动作；`naive` 自 1.13 起可用。

注意：官方文档站已跟进 1.15，文档里的 `tailcat`、MASQUE endpoint、TUN `multi_queue` 等字段在 1.14.4 中不存在；以 `sing-box schema` 的输出为准。

## 14. 与本项目生成器的对应关系

`singbox-lite` 的 `generator.uc` 只使用 Schema 的一个子集；排查生成结果时按下表对照：

| Schema 字段 | 生成器写法 | 说明 |
|---|---|---|
| `log.level` / `log.timestamp` | `main.log_level` | 日志级别与时间戳。 |
| `dns.servers[]` | `dns-direct`（udp）、`dns-proxy`（https） | 国内直连 DNS 与代理 DoH。 |
| `dns.rules[]` | `split` 模式下 `.lan/.local/.home.arpa` → `dns-direct` | DNS 分流。 |
| `dns.final` / `dns.strategy` / `dns.cache_capacity` | 按 `dns.mode` 计算 | 最终服务器、策略、缓存容量。 |
| `inbounds[0]` | `type: tun` + `auto_route`/`auto_redirect`/`dns_mode: hijack` | 唯一入站；`route_exclude_address_set` 用 `geoip-cn`。 |
| `outbounds[]` | `direct`、`selector`、`urltest`、节点 JSON | 节点 outbound 由订阅/链接原样或转换后放入。 |
| `route.rules[]` | `sniff`、`hijack-dns`、`ip_is_private`、`rule_set`/`domain_suffix`/`ip_cidr`/`port` | 规则顺序即匹配顺序；自定义规则优先。 |
| `route.rule_set[]` | `type: local`, `format: binary`, `path` | 内置/用户 `.srs`。 |
| `route.final` / `default_domain_resolver` / `auto_detect_interface` | `default` / `dns-direct` / `true` | 默认出站与 DNS。 |
| `experimental.cache_file` | `enabled: true`, `path`, `store_dns: true` | 核心缓存（含 DNS）。 |

生成后务必运行 `sing-box check -c /etc/singbox-lite/config.json`：Schema 只保证字段名/类型合法，tag 引用、端口冲突、证书路径等由 `check` 在运行时校验。

---

参考：sing-box 官方文档 <https://sing-box.sagernet.org/configuration/>；本地 Schema 由 `sing-box schema` 生成，随构建标签变化。
## 附录 A. 嵌套结构字段索引

主表未完全展开的嵌套对象在此按定义名列出字段；括号内为类型，`*` 表示必填。这些定义与 `$defs` 一一对应，可直接对照 `schema.json`。

| 定义 | 字段（类型） |
|---|---|
| `ACMEExternalAccountOptions` | `key_id`(string)、`mac_key`(string) |
| `AnyTLSUser` | `name`(string)、`password`(string) |
| `BrutalOptions` | `enabled`(boolean)、`up_mbps`(integer)、`down_mbps`(integer) |
| `CCMUser` | `name`(string)、`token`(string) |
| `CacheFileOptions` | `enabled`(boolean)、`path`(string)、`cache_id`(string)、`store_fakeip`(boolean)、`rdrc_timeout`(Duration)、`store_dns`(boolean) |
| `ClashAPIOptions` | `external_controller`(string)、`external_ui`(string)、`external_ui_download_url`(string)、`external_ui_download_detour`(string)、`secret`(string)、`default_mode`(string)、`access_control_allow_origin`(string 或 []string)、`access_control_allow_private_network`(boolean) |
| `DNS` | `servers`([]DNSServer)、`rules`([]DNSRule)、`final`(string)、`reverse_mapping`(boolean)、`strategy`(DomainStrategy)、`timeout`(Duration)、`disable_cache`(boolean)、`disable_expire`(boolean)、`cache_capacity`(integer)、`optimistic`(boolean 或 object)、`client_subnet`(string) |
| `DebugOptions` | `listen`(string)、`gc_percent`(integer)、`max_stack`(integer)、`max_threads`(integer)、`panic_on_fault`(boolean)、`trace_back`(string)、`memory_limit`(integer 或 string)、`oom_killer`(boolean) |
| `ExperimentalOptions` | `cache_file`(CacheFileOptions)、`clash_api`(ClashAPIOptions)、`v2ray_api`(V2RayAPIOptions)、`debug`(DebugOptions) |
| `HTTPProxyOptions` | `enabled`(boolean)、`server`(string)、`server_port`(integer)、`bypass_domain`(string 或 []string)、`match_domain`(string 或 []string) |
| `Hysteria2InboundRealm` | `server_url`(string)、`token`(string)、`realm_id`(string)、`stun_servers`(string 或 []string)、`ip_version`(0/4/6)、`port_mapping`(Hysteria2RealmPortMapping)、`http_client`(HTTPClientReference)、`stun_domain_resolver`(DomainResolver) |
| `Hysteria2Realm` | `server_url`(string)、`token`(string)、`realm_id`(string)、`stun_servers`(string 或 []string)、`ip_version`(0/4/6)、`port_mapping`(Hysteria2RealmPortMapping)、`http_client`(HTTPClientReference) |
| `Hysteria2RealmPortMapping` | `enabled`(boolean)、`timeout`(Duration)、`lifetime`(Duration) |
| `Hysteria2User` | `name`(string)、`password`(string) |
| `HysteriaRealmUser` | `name`(string)、`token`(string)、`max_realms`(integer) |
| `HysteriaUser` | `name`(string)、`auth`(string 或 []integer)、`auth_str`(string) |
| `InboundECHOptions` | `enabled`(boolean)、`key`(string 或 []string)、`key_path`(string) |
| `InboundMultiplexOptions` | `enabled`(boolean)、`padding`(boolean)、`brutal`(BrutalOptions) |
| `InboundRealityOptions` | `enabled`(boolean)、`handshake`(InboundRealityHandshakeOptions)、`private_key`(string)、`short_id`(string 或 []string)、`max_time_difference`(Duration) |
| `LogOptions` | `disabled`(boolean)、`level`(trace/debug/info/warn…)、`output`(string)、`timestamp`(boolean) |
| `OCMUser` | `name`(string)、`token`(string) |
| `OpenConnectCSDOptions` | `wrapper_path`(string) |
| `OpenConnectFormEntryOptions` | `form_id`(string)、`submission_key`(string)、`name`(string)、`value`(string)、`promote`(boolean) |
| `OpenConnectFortinetHostCheckOptions` | `hostcheck`(string)、`check_virtual_desktop`(string) |
| `OpenConnectHIPOptions` | `wrapper_path`(string) |
| `OpenConnectMobileOptions` | `platform_version`(string)、`device_type`(string)、`device_unique_id`(string) |
| `OpenConnectTNCCCertificateOptions` | `certificate`(string 或 []string)、`certificate_path`(string) |
| `OpenConnectTNCCOptions` | `wrapper_path`(string)、`device_id`(string)、`user_agent`(string)、`machine_identification_enabled`(boolean)、`certificates`([]OpenConnectTNCCCertificateOptions) |
| `OpenConnectTokenOptions` | `mode`(totp/hotp/stoken/oidc)、`secret`(string)、`secret_path`(string)、`pin`(string)、`password`(string)、`device_id`(string)、`counter`(integer) |
| `OpenVPNControlWrapOptions` | `type`(tls_auth/tls_crypt/tls_crypt_v2)、`key`(string 或 []string)、`key_path`(string)、`direction`(server/client) |
| `OpenVPNInboundControlWrapOptions` | `type`(tls_auth/tls_crypt/tls_crypt_v2)、`key`(string 或 []string)、`key_path`(string)、`direction`(server/client)、`force_cookie`(boolean) |
| `OpenVPNPullFilterOptions` | `action`(accept/ignore/reject)、`text`(string) |
| `OpenVPNPushDNSServerOptions` | `priority`(integer)、`addresses`(string 或 []string)、`resolve_domains`(string 或 []string)、`dnssec`(yes/optional/no)、`transport`(plain/dot/doh)、`sni`(string) |
| `OpenVPNPushOptions` | `routes`(string 或 []string)、`dns`(string 或 []string)、`dns_servers`([]OpenVPNPushDNSServerOptions)、`search_domains`(string 或 []string)、`dhcp_options`(string 或 []string)、`redirect_gateway`(boolean)、`redirect_gateway_flags`(string 或 []string)、`block_outside_dns`(boolean)、`ping_interval`(Duration)、`ping_restart`(Duration) |
| `OpenVPNRemoteOptions` | `server`(string)、`server_port`(integer)、`network`(udp/udp4/udp6/tcp…) |
| `OutboundECHOptions` | `enabled`(boolean)、`config`(string 或 []string)、`config_path`(string)、`query_server_name`(string) |
| `OutboundMultiplexOptions` | `enabled`(boolean)、`protocol`(h2mux/smux/yamux)、`max_connections`(integer)、`min_streams`(integer)、`max_streams`(integer)、`padding`(boolean)、`brutal`(BrutalOptions) |
| `OutboundRealityOptions` | `enabled`(boolean)、`public_key`(string)、`short_id`(string) |
| `OutboundUTLSOptions` | `enabled`(boolean)、`fingerprint`(chrome_psk/chrome_psk_shuffle/chrome_padding_psk_shuffle/chrome_pq…) |
| `ServerOptions` | `server`(string)、`server_port`(integer) |
| `ShadowTLSUser` | `name`(string)、`password`(string) |
| `ShadowsocksDestination` | `name`(string)、`password`(string)、`server`(string)、`server_port`(integer) |
| `ShadowsocksUser` | `name`(string)、`password`(string) |
| `SnellUser` | `name`(string)、`userkey`(string) |
| `TUICUser` | `name`(string)、`uuid`(string)、`password`(string) |
| `TrojanUser` | `name`(string)、`password`(string) |
| `TunPlatformOptions` | `http_proxy`(HTTPProxyOptions) |
| `USBIPDeviceMatch` | `bus_id`(string)、`vendor_id`(integer)、`product_id`(integer)、`serial`(string) |
| `User` | `username`(string)、`password`(string) |
| `V2RayAPIOptions` | `listen`(string)、`stats`(V2RayStatsServiceOptions) |
| `V2RayStatsServiceOptions` | `enabled`(boolean)、`inbounds`([]string)、`outbounds`([]string)、`users`([]string) |
| `VLESSUser` | `name`(string)、`uuid`(string)、`flow`(string) |
| `VMessUser` | `name`(string)、`uuid`(string)、`alterId`(integer) |
| `WireGuardPeer` | `address`(string)、`port`(integer)、`public_key`(string)、`pre_shared_key`(string)、`allowed_ips`(string 或 []string)、`persistent_keepalive_interval`(integer)、`reserved`(string 或 []integer) |

未列出的定义是 `oneOf` 联合（Inbound/Outbound/DNSServer/Endpoint/Service/Rule/RuleAction 等），已在正文按 `type` 分节展开。
