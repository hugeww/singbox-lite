# singbox-lite 代码审查（2026-11-15，0.1.0 / 4e8da30）

审查范围：`singbox-lite` 后端的 ucode 模块、init/UCI 脚本、LuCI 视图与 rpcd、测试与 CI。方法是读代码 + 运行现有测试 + 生成配置并用 sing-box 1.14.4 校验 + 针对边界做小规模复现，不是只做静态猜测。

## 结论摘要

现有主路径是通的：

- `tests/run.uc` 全部通过（`ALL TESTS PASSED`）。
- `tests/check-config.sh` 生成 TUN + auto_redirect 配置并通过 `sing-box check`。
- `tests/matrix.sh` 三种 DNS 模式都通过。
- 生成的配置与 `docs/sing-box-1.14-annotated.json5` 的主干结构一致。

但仍有几类“测试覆盖不到、特定操作必坏”的问题，按严重度排列如下。

| 级别 | 问题 | 影响 |
|---|---|---|
| P0 | 自定义出口组作为分流目标时 tag 不匹配 | LuCI 新建的自定义组一旦被规则集选中，生成配置必失败 |
| P0 | 节点指纹字段过少 | 同服务器/同 UUID、不同 ws 路径/SNI/flow 的节点被当成重复节点丢弃 |
| P0 | `postrm` 未区分升级与卸载 | 升级时可能删除托管核心并禁用开机自启 |
| P0 | 无并发锁 + 固定临时文件 | cron 刷新、手动保存、核心/插件更新互相覆盖 |
| P1 | 保存直接覆盖运行配置 | 崩溃/respawn 会应用尚未确认的配置，和“保存后重启生效”的承诺不一致 |
| P1 | 核心更新先移走旧二进制 | 写入/替换新核心失败时可能没有可执行核心 |
| P1 | `log_max_kb` 完全没有实现 | `core.log` 无上限增长，`/var/log` 在内存里 |
| P1 | DoH 缺少 `tls.server_name` | 现在靠 1.1.1.1 证书的 IP SAN 侥幸可用，换 DNS 或证书策略就会失败 |
| P1 | IPv6 面板地址拼成 `:::9090` | 配置能过 `check`，运行时 Clash API 无法监听 |
| P1 | 规则集目标允许选择不存在的国家/原生/auto 组 | 生成时报“目标出口组不存在或为空”，用户不知道是选项本身的问题 |
| P1 | 定时刷新无条件重启、重启失败不回滚 | 每 6 小时无意义中断，坏配置可能让服务停在停止状态 |
| P1 | 国家关键词边界过严 | `US01`、`JP01`、`HK01`、`native01` 全被归到 other |
| P1 | HTTPS/Clash TLS 与 SS obfs 映射缺失 | HTTPS 代理被当明文 HTTP，Clash 的 ss+obfs 插件名/参数不对 |
| P2 | 订阅/规则集下载无上限校验、规则集无完整性校验 | 大文件耗尽内存，坏 `.srs` 被持久化 |
| P2 | `core_binary` 在 init 与 `core.uc` 中语义不一致 | 校验/更新用的核心可能不是服务实际运行的那个 |
| P2 | CI 没有跑 `check-config.sh` / `matrix.sh` | 生成配置的 schema 回归进不了 CI |

---


## 补正（2026-11-15，官方 dashboard 架构）

审查和修复期间沿用了「官方 sing-box dashboard 通过 `experimental.clash_api.external_ui` 托管」的说法，这个说法不正确。官方 [SagerNet/sing-box-dashboard](https://github.com/SagerNet/sing-box-dashboard) 是 sing-box 1.14+ **sing-box API 服务**（`services[type=api]`，gRPC-Web）的 Web 客户端；API 服务通过自己的 `dashboard` 选项在 `/dashboard/` 提供静态文件，与 Clash API 无关。

当前代码已改为：`panel.dashboard=official` 时生成 `services[type=api].dashboard`，面板 URL 为 `http://<router>:port/dashboard/`；`panel.dashboard=native` 时才生成 `experimental.clash_api` 供内置 LuCI 面板使用。README 的对应描述已同步修正。


## 运行期补丁：DNS detour 空 direct 出站（2026-11-15）

`sing-box check` 不会发现、但 `sing-box run` 会立即失败的一个问题：

```text
start service: start dns-transport: start dns/udp[dns-direct]:
detour to an empty direct outbound makes no sense
```

原因是生成器把 `dns-direct` 的 `detour` 指向空 `direct` 出站（`{ "type": "direct", "tag": "direct" }`）。1.14.4 允许空 direct 作为普通路由目标，但拒绝它作为 DNS 的 detour。

修复：增加非空出站 `{ "type": "direct", "tag": "direct-dns", "tcp_fast_open": true }`，并让 `dns-direct` 使用 `detour: "direct-dns"`。已用最小配置实测：旧配置 `run` 立即 FATAL，新配置正常 `sing-box started`；`tests/check-config.sh` 增加静态断言，防止回归。

## 本轮修复状态（2026-11-15）

以下项目在本轮已改代码并通过 `tests/run.uc`、`check-config.sh`、`matrix.sh` 与 `sing-box check`：

| 项目 | 状态 | 说明 |
|---|---|---|
| 自定义出口组 target | ✅ | 生成器改用 UCI section 名作 tag；UI 只列实际存在的组，并保留“当前但暂不可用”的 target；保留名冲突 warning |
| 节点身份/去重 | ✅ | 完整 outbound 规范化指纹；旧 fingerprint 作为 legacy id 保留：无冲突节点继续用旧 ID（旧 overrides/组成员/default_node 不失效），只有冲突节点改用新 ID |
| `postrm` 升级保护 | ✅ | 只在 `$1=upgrade` 时跳过清理；APK 的 post-deinstall 无参数时仍会清理 |
| CLI 并发锁 | ✅ | `mkdir` 原子锁 + owner/stale 检测；覆盖 build/check/refresh/update-*/rulesets/rollback |
| 保存/应用分离 | ✅ | `config.json` 是草案，init 在 start/restart 时部署到 `active.json`；procd respawn 读 active，崩溃不会应用未确认配置 |
| 核心更新顺序 | ✅ | 先 stage/验证 `.new`，再备份旧核心并原子替换；失败恢复旧核心，meta 与核心 `.bak` 同步回滚 |
| `log_max_kb` | ✅（部分） | init 启动时截断 core.log 到最后 N KB，0 表示不限；`cmd_log` 改为 `tail -n`。运行中超过阈值仍需下一次 start/restart 才截断 |
| DoH TLS | ✅ | `dns-proxy` 增加 `tls.server_name=cloudflare-dns.com` |
| IPv6 Clash API | ✅ | `::`→`[::]:9090`，`::1`→`[::1]:9090`；panel API URL 同步 |
| 规则集目标选项 | ✅（部分） | UI 只提供有成员的组，保留不可用当前值；已保存的失效 target 仍会让生成器报错（不会静默丢规则） |
| 刷新 diff/回滚 | ✅ | 内容未变不重启；重启失败恢复上一份 config 并再次启动，`rolled_back=true` |
| 国家关键词边界 | ✅ | `US01/JP01/HK01/native01` 正确分类，`Russia/AUS` 不误判 |
| HTTPS/Clash TLS | ✅（部分） | HTTPS 代理、Clash http tls 保留 TLS；Clash socks5+tls 因 sing-box 1.14.4 socks 无 tls 字段，改为跳过并 warning |
| 下载上限/完整性 | ✅ | curl `--max-filesize`（订阅 5MB、规则集 16MB）；.srs 校验 `SRS` magic，坏包不覆盖旧文件 |
| CI 配置校验 | ✅ | 新增 sing-box 1.14.4 下载 + `check-config.sh`/`matrix.sh` job |
| `unzip` 依赖 | ✅ | `singbox-lite` 增加 `+unzip` |
| 日志权限 | ✅ | init `umask 077`，日志目录/文件仅 root |
| 死代码/无用依赖 | ✅ | 移除 `used_file_tags`、未用 import、`ruleset_files_for_validation`、`ucode-mod-ubus/digest` |

尚未处理（记录在案，避免误以为全部完成）：

- `main.core_binary` 在 init 与 `core.uc` 中语义仍不一致（init 优先使用，CLI 忽略）；需要确认是否保留该遗留选项。
- `panel_delay` 仍串行请求最多 12 个成员，最坏可能超过 rpcd 超时；建议并发/缩短超时。
- `keep.d/singbox-lite` 仍备份整个 `/etc/singbox-lite/`（含 cache.db）。
- Clash API 默认 `0.0.0.0:9090` 的暴露面未改变（有随机 secret；如强化安全可默认 127.0.0.1，官方 dashboard 再显式改监听）。
- 日志运行中超过 `log_max_kb` 不会实时轮转，只在下一次 start/restart 截断。
- 节点 ID 冲突场景（同 legacy id 的多个不同节点）旧 group/override 只能通过 legacy 别名命中第一个；新 UI 使用新 ID。
- `rulesets.js` 已保存但当前不可用的 target 会显示 `(unavailable)`，但生成器仍会硬错误；不会静默改路由。
- JSON5 模板里的 `ntp`/`certificate*`/`http_clients`/`network_namespaces`/`services` 仍不由表单生成，属手工/高级配置；`endpoints` 目前只由「Tailscale」页生成 `type: tailscale`，其余 endpoint 类型仍靠手工。

---

## P0-1 自定义出口组作为目标时 tag 不匹配

**现象**：在 LuCI 新建一个自定义出口组，把某个规则集的目标设为该组，保存时生成失败：

```text
规则集 Example 的目标出口组 new1a2b3c 不存在或为空
```

**原因**：

- `rulesets.js:21` 把 UCI section 名直接放进 target 选项：`option.value(g['.name'], ...)`。
- LuCI 新建 section 的 id 是 `new%06x`（见 LuCI `uci.js` 的 `createSID()`），例如 `new1a2b3c`。
- `generator.uc:55,120` 的 `custom_group_tag()` 会再加 `eg_` 前缀，生成 tag `eg_new1a2b3c`。
- 生成器的 `group_tags` 只有 `eg_new1a2b3c`，而规则 target 是 `new1a2b3c`，于是 `generator.uc:168` 直接报错。

**复现**：把 `tests/cli-config.json` 的 `egress_groups[0]['.name']` 和 `rulesets[0].target` 都改成 `new1a2b3c`，`preview` 返回上述错误。

**修复建议**：生成器和 UI 共用一个“组 tag”规则。最直接的是生成器直接使用 section 名作为 tag（只做字符白名单/保留名检查），不再额外加 `eg_`；或者 UI 也调用同样的 slug 逻辑并展示 `eg_...`。同时加一条回归测试：`new1a2b3c` 作为 target 必须能生成成功。

---

## P0-2 节点指纹过粗，合法节点被去重

**现象**：同一服务器、同一端口、同一 UUID，但 ws 路径不同（`/ws1` 与 `/ws2`）的两个 VMess 节点，被 `collect_nodes` 当成重复节点，只保留一个：

```text
nodes=1 warnings=[ "重复节点已跳过：B（来源 手动节点）" ]
```

**原因**：`nodes.uc:53-63` 的 `node_fingerprint()` 只取：

```text
type | server | server_port | uuid 或 password/method
```

没有包含 `transport`、`tls.server_name`、`reality`、`flow`、`security`、`alter_id`、`obfs`、`plugin` 等字段。两个节点的 fingerprint 实测都是 `79643e40`。

**影响**：机场经常用同一台服务器、同一个 UUID，靠不同 ws path / SNI / flow 区分多个节点；这些节点会静默消失，用户只会看到“重复节点已跳过”的警告。

**修复建议**：把整个 outbound（去掉 `tag`/`name`）做规范化 JSON 后哈希，或至少把 transport/TLS/flow/security/obfs/plugin 全部纳入。加两条同服务器不同 path 的测试。

---

## P0-3 `postrm` 没有区分升级与卸载

`singbox-lite/Makefile:78-84`：

```sh
define Package/singbox-lite/postrm
...
/etc/init.d/singbox-lite stop ...
/etc/init.d/singbox-lite disable ...
sed -i '/# singbox-lite/d' /etc/crontabs/root ...
rm -rf /usr/libexec/singbox-lite
exit 0
endef
```

OpenWrt 的包脚本会带 `$1`（`remove` / `upgrade`）。这段没有判断 `$1`，如果升级路径以 `upgrade` 调用 `postrm`，就会：

- 删除 `/usr/libexec/singbox-lite`，也就是用户下载的托管核心；
- 清掉开机自启；
- 清掉 cron 刷新任务。

**修复建议**：

```sh
[ "$1" = "remove" ] || exit 0
```

把“仅卸载时清理”的逻辑放到 guard 之后；升级时保留核心、自启和 cron。

---

## P0-4 无并发锁、固定临时路径

**证据**：

- `common.uc:32` 定义了 `PATH.lock`，但全仓库没有任何地方使用它。
- `cli.uc:81` 使用固定 `PATH.config_json + '.tmp'`。
- `subs.uc` 使用 `/tmp/singbox-lite/<section>.body` / `.hdr`；`parse_clash_body` 使用固定 `clash-sub.yaml`。
- `core.uc` 使用固定 `sing-box.tar.gz` / `core-extract`；`plugin.uc`、`panel.uc` 同理。

**影响**：cron 的 `refresh --all` 与用户在 LuCI 点“保存并检查”、或后台核心/插件更新同时发生时，可能互相覆盖临时文件、配置或状态文件。典型结果是生成到一半的 config 被另一个进程 rename 成正式配置，或者 `sing-box.tar.gz` 被另一个下载覆盖。

**修复建议**：在 CLI 入口对 `build`/`refresh`/`update-core`/`update-plugin`/`update-dashboard` 加互斥锁（`flock` 或基于 `PATH.lock` 的原子 mkdir 锁，带超时和 stale 清理），临时文件名带 PID，状态文件也要原子写。

---

## P1-1 保存直接覆盖运行配置，respawn 会应用未确认配置

`cli.uc:77-94` 的 `save_config()` 把生成结果 rename 到 `PATH.config_json`；这正是 init 脚本 `-c` 读取的文件（`init.d:72`）。UI 的提示是“Saved. Restart the service to apply.”。

问题在于 procd 配置了 `respawn 3600 5 5`（`init.d:75`）：进程崩溃后 procd 会用**同一个 config 路径**重新拉起，新配置会在没有用户点“重启”的情况下生效。也就是说“保存”与“应用”只在正常运行期间分离，崩溃/异常重启时会穿透。

**修复建议**：恢复 draft/active 分离：生成写 `config.draft.json`（或 `profiles/`），显式 start/restart 时才原子替换 `active.json`；init 只读 active。或者至少让保存写到 `.next`，启动脚本负责部署。

---

## P1-2 核心更新先移走旧二进制

`core.uc:205-221` 的顺序是：

```text
unlink(core_bak)
rename(core, core_bak)      // 旧核心先被移走
write_binary(staged, new)   // 之后才写新核心
rename(staged, core)
```

如果 `write_binary` 失败（磁盘满、权限、cp 失败），`PATH.core` 已经不存在，`core_bak` 还在，但函数直接返回错误，没有恢复。服务如果正在运行不受影响，但下次启动/重启就会找不到核心。

**修复建议**：先写 `core.new` 并校验，再 `rename(core, core_bak)`，再 `rename(core.new, core)`；任一步失败都恢复旧核心。`rollback_core()` 也同样要避免“先删再 rename”的中间态。

---

## P1-3 `log_max_kb` 是死设置，`core.log` 无上限

- 默认配置 `singbox-lite/files/etc/config/singbox-lite:11` 有 `log_max_kb '2048'`。
- 设置页 `settings.js:233` 暴露了“Log max size (KB)”。
- 但后端没有任何地方读取它（全仓库 grep 只命中这两处）。
- init 脚本用 `>> "$SINGBOX_LITE_LOG"` 追加（`init.d:72`），`core.log` 永远不会轮转；`/var/log` 在 OpenWrt 上是 tmpfs，会占内存。
- `cmd_log()` 还会把整个日志读进内存再切最后 N 行。

**修复建议**：在写日志前按 `log_max_kb` 截断/轮转（例如 init 启动时 `tail -c`，或 CLI 每次 refresh 时截断），`cmd_log` 用 `tail` 读取尾部而不是全量读。也可以先把这个设置从 UI 移除，避免“设置了但没用”。

---

## P1-4 DoH 缺少 `tls.server_name`

生成器 `generator.uc:211`：

```json
{ "type": "https", "tag": "dns-proxy", "server": "1.1.1.1", "detour": "default" }
```

而 JSON5 模板（`docs/sing-box-1.14-annotated.json5:99`）写的是：

```json
"tls": { "enabled": true, "server_name": "cloudflare-dns.com" }
```

现在能工作，是因为 Cloudflare 的 1.1.1.1 证书包含 IP SAN；一旦换 DNS 服务器、证书不带 IP SAN，或出于反审查希望发送固定 SNI，就会失败/暴露为 IP 直连特征。

**修复建议**：补 `tls.server_name`。更稳妥的是把 `server` 写成 `cloudflare-dns.com`，并加 `domain_resolver: "dns-direct"`。

---

## P1-5 IPv6 面板地址无效

生成器 `generator.uc:258`：

```ucode
external_controller: listen + ':' + port
```

当 `panel.listen` 是 `::` 或 `::1` 时得到 `:::9090` 或 `::1:9090`。实测 `sing-box check` 接受这个字符串，但运行时 Clash API 无法按该地址监听；`panel.uc:155` 的 `http://` + host + `:` + port 对 `::1` 同样无效。

**修复建议**：检测 IPv6 字面量并加方括号：`[::]:9090`、`[::1]:9090`；`panel.uc` 的 `api()` 也要对 host 做同样处理。加测试覆盖 `::`、`::1`、`0.0.0.0`、域名四种 listen。

---

## P1-6 规则集目标允许选择不存在的组

`rulesets.js:9-21` 的 `addTargets()` 无条件提供：`direct/default/auto/us/jp/hk/other/native` + 所有自定义组。但生成器：

- 只有 `groups[c]` 非空才创建 `us`/`jp`/`hk`/`other` 组（`generator.uc:81-89`）；
- 只有存在原生节点才创建 `native`（`:91-96`）；
- `auto` 在非原生节点为 0 或超过 200 时会被跳过（`:64-73`）。

用户选了一个没有成员的组，生成直接失败。示例：只有 US/JP/HK 节点时把“开发”规则集目标设为 `other`，得到：

```text
规则集 开发 的目标出口组 other 不存在或为空
```

**修复建议**：规则集页加载 `api.status()`，只展示实际存在且有成员的组；或者在生成器里把“目标不存在”降级为 warning 并跳过该规则，同时在 UI 明确提示。两者选其一，不要静默失败。

---

## P1-7 定时刷新无条件重启，失败不回滚

`cli.uc:196-205`：

```ucode
let saved = save_config(cfg, gen);
if (saved.ok) {
  sync_cron(cfg);
  if (service_running() && auto_apply) {
    let rc = system([PATH.init, 'restart']);
    status.restarted = (rc == 0 && service_running());
  }
}
```

问题：

1. 没有比较新旧配置。每 6 小时即使订阅内容没变也会重启一次，短暂中断。
2. 重启失败只把 `restarted=false` 写进状态，没有把 `config.json.bak` 恢复回去，服务可能停在停止状态。
3. 校验通过不等于能启动（端口冲突、远程 rule_set 下载失败、核心 build 缺少组件），所以“失败回滚”不能只依赖 `check`。

**修复建议**：先比较生成 JSON 与现配置的哈希，相同则跳过写盘/重启；重启失败时自动回滚 `config.json.bak` 并再次尝试启动，或至少暴露“回滚并启动”命令/UI。把 `restart` 的结果纳入 `ok`，不要只写状态字段。

---

## P1-8 国家关键词边界过严

`nodes.uc:20-29` 对 ASCII 关键词使用：

```text
(^|[^a-z0-9])keyword([^a-z0-9]|$)
```

实测：

```text
US01=other  US-01=us  US 01=us  JP01=other  HK01=other  native01=other
```

机场常把节点命名为 `US01`、`JP01`、`HK01`、`native01`，这些全部落到 other，影响国家组、默认组和原生识别。

**修复建议**：对短国家码/英文关键词，边界改成“非字母”而不是“非字母数字”，例如 `(^|[^a-z])keyword([^a-z]|$)`；同时保留 `Russia`/`AUS` 不被误匹配的测试。中文关键词走 `index()` 不受影响。

---

## P1-9 链接/Clash 解析丢失 TLS 与 SS obfs 映射

已实测：

1. `https://user:pass@proxy:443` 被解析成 `type: http`，`tls=null`。HTTPS 代理被当明文 HTTP 用。
2. Clash `type: http, tls: true` 经 `clash_to_outbound` 后没有 `tls`；`socks5 + tls` 同样。
3. Clash `type: ss`、`plugin: obfs`、`plugin-opts: {mode: http, host: bing.com}` 被输出为：
   ```json
   "plugin": "obfs", "plugin_opts": "mode=http;host=bing.com"
   ```
   而 sing-box 的 Shadowsocks 插件是 `obfs-local`，参数应为 `obfs=http;obfs-host=bing.com`。节点能生成，但运行时会因为插件不存在/参数不对而连不上。

**修复建议**：

- `parse_http(u, scheme)` 在 `https` 时补 `tls: {enabled: true, server_name: u.host}`（或明确拒绝 https 链接并给 warning）。
- Clash http/socks 分支检测 `p.tls`，补 `clash_tls()`。
- SS 插件按名字映射：`obfs` → `obfs-local`，`mode` → `obfs`，`host` → `obfs-host`；`v2ray-plugin` 单独映射；未知插件给出 warning。
- 补对应 fixture 测试。

---

## P1-10 订阅与规则集下载没有大小上限/完整性校验

- `subs.uc:119` 的 5MB 限制是在 `curl` 已经把完整 body 写到磁盘、再 `read_text` 之后才检查的；`shell_http_get` 没有 `--max-filesize`，恶意/异常订阅可以先写满 `/tmp`。
- `rulesets.uc:172-200` 的远程 `.srs` 只检查 HTTP 200 和文件非空，不校验 magic/格式/大小；下载到 HTML 错误页也会被 rename 成 `.srs`，下一次生成直接引用坏文件。
- `update_builtin_rulesets` 同样没有校验。

**修复建议**：`shell_http_get` 增加 `--max-filesize`；对 `.srs` 检查最小大小/格式（如 `sing-box rule-set` 工具或已知 magic），失败保留旧文件；内置更新先下载到临时目录，全部成功后再替换。

---

## P2 其他值得处理的问题

### `core_binary` 语义不一致

init 的 `core_path()`（`init.d:19-33`）会优先使用 UCI `main.core_binary`；`core.uc:26-29` 的 `core_path(cfg)` 完全忽略它。结果：CLI 的 `check/build/update-core` 可能校验/更新托管核心，而 init 启动的是另一个自定义核心。要么统一支持 `core_binary`，要么在 uci-defaults 里删除这个遗留选项。

### CI 不跑生成配置校验

`.github/workflows/build.yml` 的 host tests 只跑 `tests/run.uc`、JS 语法和 ucode 编译；`tests/check-config.sh` / `tests/matrix.sh` 需要手动下载核心，没有进 CI。建议加一个 job：下载 sing-box 1.14.4 二进制，跑两个脚本；这能挡住字段名/类型回归（虽然挡不住运行时连通性）。

### 面板延迟接口可能超时

`panel_delay()` 对最多 12 个成员串行请求，每个 `--max-time 10`，最坏 120 秒，远超 rpcd/LuCI 的常见超时。建议并发（有限度）或每个 2–3 秒，并在 UI 显示进度。

### 官方面板依赖 `unzip` 未声明

`panel.uc:96` 会检查 `unzip`，缺失时提示安装，但 `singbox-lite` 的 `DEPENDS` 没有 `+unzip`（`Makefile:17-19`）。默认面板是 official，用户很可能第一次下载就失败。加依赖或用 busybox 自带解压方案。

### 日志权限与 API 暴露

- `/var/log/singbox-lite` 由 init `mkdir -p`，默认 755；`core.log` 由 shell 重定向创建，默认 644。日志含域名/SNI，建议目录 700、文件 600。
- `panel.listen` 默认 `0.0.0.0:9090`，虽然有随机 secret，但 API 是明文 HTTP。建议默认 127.0.0.1，用户选官方 dashboard 时再明确提示改监听地址；至少不要让 `secret` 为空时生成配置（现在 generator 只 warning）。

### 死代码/依赖

- `PATH.lock`（`common.uc:32`）未使用。
- `generator.uc:5` 导入 `rule_set_tag` 但未使用；`:162` `used_file_tags` 只写不读。
- `rulesets.uc:217` `ruleset_files_for_validation` 未使用。
- `ucode-mod-digest`、`ucode-mod-ubus` 在代码里没有对应使用（依赖可精简）。
- `log_max_kb` 见 P1-3。

### `keep.d` 把缓存也带进 sysupgrade 备份

`keep.d/singbox-lite` 保留整个 `/etc/singbox-lite/`，包括 `cache.db`（可能数十 MB）和订阅原始内容。sysupgrade 备份会变大；建议只保留 `config.json`/必要元数据，或把 cache 放到 `/var`。

---

## 与 JSON5 模板的对照结论

`docs/sing-box-1.14-annotated.json5` 描述的是 1.14.4 的完整能力，而 `generator.uc` 只生成其中一部分：

| JSON5 块 | 生成器是否生成 | 说明 |
|---|---|---|
| `log` | 是 | 仅 level/timestamp |
| `dns` | 是 | 两个服务器 + 规则，缺 DoH TLS server_name |
| `inbounds` | 是 | 仅 tun；mixed/其它协议是手工模板 |
| `outbounds` | 是 | direct/selector/urltest + 链接解析出的节点 |
| `route` | 是 | 规则/规则集/默认出口 |
| `experimental` | 是 | cache_file（+ 可选 clash_api） |
| `endpoints`（tailscale） | 是 | 「Tailscale」页开关，含 MagicDNS 与 preferred_by 路由规则 |
| `endpoints`（wireguard/openvpn/openconnect 等） | 否 | 仅文档/手工高级配置 |
| `ntp` / `certificate` / `certificate_providers` / `http_clients` / `network_namespaces` / `services` | 否 | 仅文档/手工高级配置 |

建议在 JSON5 模板顶部明确标注“生成器只覆盖 log/dns/inbounds/outbounds/route/experimental；其余块需要手工/仅核心模式”，避免用户以为表单能配置全部。

---

## 建议的修复顺序

1. **P0（先做）**：自定义组 tag、节点指纹、postrm guard、并发锁。
2. **P1（一个版本内）**：保存/应用分离、core 替换顺序、日志轮转、DoH TLS、IPv6、目标组校验、刷新 diff + 回滚、关键词边界、链接/Clash TLS、下载上限。
3. **P2（持续）**：CI 加 `check-config`、`unzip` 依赖、面板延迟、日志权限、死代码/依赖清理、keep.d 范围。

## 建议新增的测试

- 自定义组 section 名 `new1a2b3c` 作为规则集 target 必须生成成功。
- 两个同 server/UUID、不同 ws path/SNI/flow 的节点必须都保留。
- `US01`/`JP01`/`HK01`/`native01` 的国家/原生分类。
- `panel.listen` = `::` / `::1` 生成合法 controller。
- `https://` 代理和 Clash `tls: true` 的 http/socks 必须带 `tls`。
- Clash `ss + obfs` 映射为 `obfs-local` + `obfs-host`。
- 订阅超过 5MB 时在下载阶段失败，而不是先落盘。
- `log_max_kb` 生效后 `core.log` 不超过阈值。
- 生成配置的 `sing-box check` 进 CI。

---

## 复现记录（摘要）

- 自定义组目标：`new1a2b3c` → `规则集 Example 的目标出口组 new1a2b3c 不存在或为空`。
- 节点指纹：两个 VMess 节点 fingerprint 都是 `79643e40`；`collect_nodes` 输出 `nodes=1`，警告“重复节点已跳过：B”。
- 关键词：`US01=other`、`JP01=other`、`HK01=other`、`native01=other`；`US-01=us`。
- IPv6：`panel.listen='::'` 生成 `external_controller: ":::9090"`。
- HTTPS 代理：`parse_link('https://...')` 得到 `type=http`、`tls=null`。
- Clash HTTP TLS：`clash_to_outbound({type:'http', tls:true})` 没有 `tls`。
- Clash SS obfs：输出 `plugin: "obfs"`、`plugin_opts: "mode=http;host=bing.com"`。
