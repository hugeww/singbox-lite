'use strict';

import { readfile } from 'fs';
import { parse_link, parse_manual_input, clash_to_outbound } from 'sbx_links';
import { parse_body } from 'sbx_subs';
import { classify_country, is_native, node_fingerprint, legacy_fingerprint, node_tag, override_key, collect_nodes, group_nodes } from 'sbx_nodes';
import { build_config } from 'sbx_generator';
import { resolve_rulesets } from 'sbx_rulesets';
import { arch_asset, version_ge, migrate_config_for_core } from 'sbx_core';
import { parse_tags, parse_release_page, mirror_url } from 'sbx_releases';
import { asset_name, download_url, base_version, parse_apk_list, parse_apk_db } from 'sbx_plugin';
import { pct, proxy_groups, connection_list, panel_config, panel_status, last_delay, dashboard_archive_url, dashboard_selected } from 'sbx_panel';
import { PATH, mkdir_p, write_json } from 'sbx_common';

let failures = 0;
function check(cond, msg) {
	if (!cond) { failures++; printf('FAIL: %s\n', msg); }
	else printf('ok: %s\n', msg);
}

function fixture(name) {
	let p = (getenv('SINGBOX_LITE_TESTDIR') || '.') + '/tests/fixtures/' + name;
	return readfile(p) || '';
}

/* link parser */
let vless = parse_link('vless://11111111-1111-1111-1111-111111111111@example.com:443?security=reality&sni=example.com&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=01&type=grpc&serviceName=grpc#Reality%20Node');
check(vless.ok && vless.type == 'vless' && vless.name == 'Reality Node', 'vless/reality parse');
check(vless.outbound.tls.reality.enabled && vless.outbound.tls.utls.enabled, 'reality requires uTLS');
let trojan = parse_link('trojan://pass@example.org:443?sni=example.org&type=ws&path=%2Fws&host=example.org#T');
check(trojan.ok && trojan.outbound.transport.path == '/ws', 'trojan ws parse');
let ss = parse_link('ss://YWVzLTI1Ni1nY206cGFzcw@example.net:8388#SS');
check(ss.ok && ss.outbound.method == 'aes-256-gcm', 'ss parse');
let hy = parse_link('hysteria2://pass@example.net:443?sni=example.net&insecure=1&obfs=salamander&obfs-password=x#H');
check(hy.ok && hy.outbound.obfs.type == 'salamander', 'hysteria2 parse');
let tuic = parse_link('tuic://11111111-1111-1111-1111-111111111111:pw@example.net:443?sni=example.net&alpn=h3#TUIC');
check(tuic.ok && tuic.outbound.tls.alpn[0] == 'h3', 'tuic parse');
let bad = parse_link('ssr://abc');
check(!bad.ok, 'unsupported protocol rejected');
let httpsProxy = parse_link('https://u:p@proxy.example.com:443#proxy');
check(httpsProxy.ok && httpsProxy.outbound.tls && httpsProxy.outbound.tls.enabled, 'https proxy gets tls');
let clashHttpTls = clash_to_outbound({ type: 'http', server: 'proxy.example.com', port: 443, username: 'u', password: 'p', tls: true });
check(clashHttpTls && clashHttpTls.tls && clashHttpTls.tls.enabled, 'clash http tls kept');
check(clash_to_outbound({ type: 'socks5', server: 'proxy.example.com', port: 1080, tls: true }) == null, 'clash socks5 tls skipped (unsupported by sing-box)');
let clashSsObfs = clash_to_outbound({ type: 'ss', server: 'ss.example.com', port: 8388, cipher: 'aes-256-gcm', password: 'p',
	plugin: 'obfs', 'plugin-opts': { mode: 'http', host: 'bing.com' } });
check(clashSsObfs && clashSsObfs.plugin == 'obfs-local' && match(clashSsObfs.plugin_opts, /obfs=http/) != null && match(clashSsObfs.plugin_opts, /obfs-host=bing\.com/) != null, 'clash ss obfs mapped to obfs-local');
let clashSsV2 = clash_to_outbound({ type: 'ss', server: 'ss.example.com', port: 8388, cipher: 'aes-256-gcm', password: 'p',
	plugin: 'v2ray-plugin', 'plugin-opts': { mode: 'websocket', host: 'cdn.example.com', path: '/ws', tls: true } });
check(clashSsV2 && clashSsV2.plugin == 'v2ray-plugin' && match(clashSsV2.plugin_opts, /mode=websocket/) != null && match(clashSsV2.plugin_opts, /tls/) != null, 'clash v2ray-plugin mapped');

/* hysteria2 bandwidth / port hopping (URI and Clash spellings) */
let hy2 = parse_link('hysteria2://pass@hy.example.net:443?sni=hy.example.net&upmbps=100&downmbps=500&mport=1000-2000&hop-interval=30s#HY2');
check(hy2.ok && hy2.outbound.up_mbps == 100 && hy2.outbound.down_mbps == 500, 'hysteria2 URI bandwidth parsed');
check(hy2.ok && length(hy2.outbound.server_ports || []) == 1 && hy2.outbound.server_ports[0] == '1000:2000', 'hysteria2 URI port hopping parsed');
check(hy2.ok && hy2.outbound.hop_interval == '30s', 'hysteria2 URI hop interval parsed');
let hy2Clash = clash_to_outbound({ type: 'hysteria2', server: 'hy.example.net', port: 443, password: 'pw', sni: 'hy.example.net',
	up: 100, down: 500, ports: '1000-2000', 'hop-interval': '30s' });
check(hy2Clash != null && hy2Clash.up_mbps == 100 && hy2Clash.down_mbps == 500, 'clash hysteria2 bandwidth mapped');
check(hy2Clash != null && length(hy2Clash.server_ports || []) == 1 && hy2Clash.server_ports[0] == '1000:2000', 'clash hysteria2 port hopping mapped');
check(hy2Clash != null && hy2Clash.hop_interval == '30s', 'clash hysteria2 hop interval mapped');

/* subscription formats */
let base = parse_body(fixture('base64-sub.txt'), 'auto');
check(base.ok && length(base.nodes) == 6, 'base64 subscription');
let plain = parse_body(fixture('plain-links.txt'), 'auto');
check(plain.ok && length(plain.nodes) == 6, 'plain URI subscription');
let jsonSub = parse_body(fixture('singbox-sub.json'), 'auto');
check(jsonSub.ok && length(jsonSub.nodes) == 1, 'sing-box JSON subscription');
let html = parse_body(fixture('bad.html'), 'auto');
check(!html.ok, 'HTML subscription rejected');

/* regression: dirty optional fields and missing credentials in JSON subscriptions */
let dirtyJson = sprintf('%J', { outbounds: [
	{ type: 'vmess', tag: 'VM', server: 'vm.example.com', server_port: 443, uuid: '66666666-6666-6666-6666-666666666666',
		transport: [], multiplex: {}, tls: { enabled: true, server_name: 'vm.example.com' } },
	{ type: 'vless', tag: 'no-uuid', server: 'nouuid.example.com', server_port: 443, tls: { enabled: true } },
	{ type: 'trojan', tag: 'no-pass', server: 'nopass.example.com', server_port: 443 },
	{ type: 'vless', tag: 'WS', server: 'ws.example.com', server_port: 443, uuid: '88888888-8888-8888-8888-888888888888', transport: { type: 'ws', path: '/ws' } },
	{ type: 'vless', tag: 'Good', server: 'ok.example.com', server_port: 443, uuid: '77777777-7777-7777-7777-777777777777' }
] });
let dirtySub = parse_body(dirtyJson, 'auto');
check(dirtySub.ok && length(dirtySub.nodes) == 3, 'JSON nodes missing credentials skipped');
function sub_node(list, name) {
	for (let n in (list || [])) if (n.name == name) return n;
	return null;
}
let dirtyVm = sub_node(dirtySub.nodes, 'VM');
check(dirtyVm != null && dirtyVm.outbound.transport == null && dirtyVm.outbound.multiplex == null && dirtyVm.outbound.tls != null, 'empty transport/multiplex cleaned from JSON node');
let dirtyWs = sub_node(dirtySub.nodes, 'WS');
check(dirtyWs != null && dirtyWs.outbound.transport != null && dirtyWs.outbound.transport.path == '/ws', 'real transport kept in JSON node');
check(sub_node(dirtySub.nodes, 'Good') != null, 'valid JSON node kept');

/* regression: Clash-style JSON subscriptions go through the same cleaning/credential rules */
let clashStyleBad = parse_body('{"proxies":[{"type":"trojan","server":"t.example.com","port":443}]}', 'auto');
check(!clashStyleBad.ok && length(clashStyleBad.nodes) == 0, 'clash-style JSON node missing credentials rejected');
let clashBadWarn = join('\n', clashStyleBad.warnings);
check(index(clashBadWarn, '跳过缺少凭据的节点：t.example.com（t.example.com:443）') >= 0, 'clash-style JSON missing credentials reported');

let clashStyleOk = parse_body(sprintf('%J', { proxies: [
	{ type: 'vmess', name: 'CVM', server: 'cvm.example.com', port: 443, uuid: '99999999-9999-9999-9999-999999999999', cipher: 'auto', transport: [] },
	{ type: 'ss', name: 'CSS', server: 'css.example.com', port: 8388, cipher: 'aes-256-gcm', password: 'pw' }
] }), 'auto');
check(clashStyleOk.ok && length(clashStyleOk.nodes) == 2, 'valid clash-style JSON nodes kept');
let clashVm = sub_node(clashStyleOk.nodes, 'CVM');
check(clashVm != null && clashVm.outbound.transport == null, 'clash-style vmess outbound has no transport');
let clashSs = sub_node(clashStyleOk.nodes, 'CSS');
check(clashSs != null && clashSs.outbound.method == 'aes-256-gcm' && clashSs.outbound.password == 'pw', 'valid encrypted clash-style ss kept');

/* SS method=none needs no password; encrypted SS still requires one */
let ssNone = parse_body(sprintf('%J', { proxies: [
	{ type: 'ss', name: 'SS-NONE', server: 'none.example.com', port: 8388, cipher: 'none' }
] }), 'auto');
check(ssNone.ok && length(ssNone.nodes) == 1 && ssNone.nodes[0].name == 'SS-NONE', 'ss method=none without password kept');
let ssNoPw = parse_body(sprintf('%J', { proxies: [
	{ type: 'ss', name: 'SS-NOPW', server: 'nopw.example.com', port: 8388, cipher: 'aes-128-gcm' }
] }), 'auto');
check(!ssNoPw.ok && length(ssNoPw.nodes) == 0, 'encrypted ss without password skipped');
check(index(join('\n', ssNoPw.warnings), '跳过缺少凭据的节点：SS-NOPW（nopw.example.com:8388）') >= 0, 'encrypted ss missing password reported');

/* node classification */
let egress = { us_keywords: '美国,US,USA', jp_keywords: '日本,JP', hk_keywords: '香港,HK', native_keywords: '原生,原生IP,native' };
check(classify_country('🇺🇸 美国 洛杉矶 01', egress) == 'us', 'US country classification');
check(classify_country('日本 东京 01', egress) == 'jp', 'JP country classification');
check(classify_country('HK-01', egress) == 'hk', 'HK country classification');
check(classify_country('Singapore', egress) == 'other', 'other country classification');
check(is_native('原生 IP 01', egress), 'native keyword');
check(!is_native('normal 01', egress), 'non-native keyword');
check(classify_country('US01', egress) == 'us' && classify_country('JP01', egress) == 'jp' && classify_country('HK01', egress) == 'hk', 'country code with digits classified');
check(classify_country('Russia', egress) == 'other' && classify_country('AUS', egress) == 'other', 'country code inside word not matched');
check(is_native('native01', egress), 'native keyword with digits');

/* readable tags + info-node filtering */
check(node_tag('香港 01', 'abc12345') == '香港 01 [abc12345]', 'node tag keeps readable name');
check(node_tag('   ', 'abc12345') == 'node [abc12345]', 'node tag falls back to node');

let infoCfg = {
	main: { log_level: 'info', info_keywords: '' },
	egress: egress,
	subscriptions: [],
	node_overrides: [],
	nodes: [
		{ '.name': 'info1', enabled: '1', link: 'vless://11111111-1111-1111-1111-111111111111@info.example.com:443?security=tls&sni=info.example.com#剩余流量：348.39 GB' },
		{ '.name': 'info2', enabled: '1', link: 'vless://11111111-1111-1111-1111-111111111111@info2.example.com:443?security=tls&sni=info2.example.com#如果很少节点可用，去官网更新软件' },
		{ '.name': 'info3', enabled: '1', link: 'vless://11111111-1111-1111-1111-111111111111@info3.example.com:443?security=tls&sni=info3.example.com#建议每天更新一次订阅' },
		{ '.name': 'real', enabled: '1', link: 'vless://11111111-1111-1111-1111-111111111111@real.example.com:443?security=tls&sni=real.example.com#美国 洛杉矶 01' }
	]
};
let infoCollected = collect_nodes(infoCfg);
check(length(infoCollected.nodes) == 1, 'info nodes skipped');
check(infoCollected.nodes[0] && infoCollected.nodes[0].name == '美国 洛杉矶 01', 'real node kept');
check(length(infoCollected.warnings) == 3, 'info nodes reported as warnings');
check(index(join('\n', infoCollected.warnings), '已跳过信息节点：建议每天更新一次订阅') >= 0, 'update-notice info node skipped');

/* regression: subscription entries with info banners / loopback / invalid ports are dropped */
mkdir_p(PATH.meta_dir);
write_json(PATH.meta_dir + '/regress_sub.json', { nodes: [
	{ name: '建议每天更新一次订阅', type: 'vless', server: 'notice.example.com', server_port: 443,
		outbound: { type: 'vless', server: 'notice.example.com', server_port: 443, uuid: '22222222-2222-2222-2222-222222222222', tls: { enabled: true, server_name: 'notice.example.com' } } },
	{ name: '本机占位', type: 'vless', server: '127.0.0.1', server_port: 20004,
		outbound: { type: 'vless', server: '127.0.0.1', server_port: 20004, uuid: '33333333-3333-3333-3333-333333333333', tls: { enabled: true, server_name: 'local' } } },
	{ name: '端口非法', type: 'vless', server: 'badport.example.com', server_port: 70000,
		outbound: { type: 'vless', server: 'badport.example.com', server_port: 70000, uuid: '44444444-4444-4444-4444-444444444444', tls: { enabled: true, server_name: 'badport.example.com' } } },
	{ name: '订阅正常节点', type: 'vless', server: 'sub.example.com', server_port: 443,
		outbound: { type: 'vless', server: 'sub.example.com', server_port: 443, uuid: '55555555-5555-5555-5555-555555555555', tls: { enabled: true, server_name: 'sub.example.com' } } }
] });
let regressCfg = {
	main: { info_keywords: '' }, egress: egress,
	subscriptions: [ { '.name': 'regress_sub', name: 'Regress', enabled: '1' } ],
	nodes: [], node_overrides: []
};
let regressCol = collect_nodes(regressCfg);
let regressWarn = join('\n', regressCol.warnings);
check(length(regressCol.nodes) == 1 && regressCol.nodes[0].name == '订阅正常节点', 'unusable subscription nodes skipped');
check(index(regressWarn, '已跳过不可用的订阅节点：本机占位（127.0.0.1:20004）') >= 0, 'loopback subscription node reported');
check(index(regressWarn, '已跳过不可用的订阅节点：端口非法（badport.example.com:70000）') >= 0, 'invalid subscription port reported');
check(index(regressWarn, '已跳过信息节点：建议每天更新一次订阅') >= 0, 'subscription update-notice node reported');

/* loopback filtering is subscription-only: a manual local proxy must be kept */
let localCfg = {
	main: { info_keywords: '' }, egress: egress, subscriptions: [], node_overrides: [],
	nodes: [ { '.name': 'local', name: '本机代理', enabled: '1', link: 'vless://11111111-1111-1111-1111-111111111111@127.0.0.1:443?security=tls&sni=local#本机代理' } ]
};
let localCol = collect_nodes(localCfg);
check(length(localCol.nodes) == 1 && localCol.nodes[0].server == '127.0.0.1' && length(localCol.warnings) == 0, 'manual loopback node kept');

/* node overrides: sections written by the LuCI Nodes page */
let olink = 'vless://11111111-1111-1111-1111-111111111111@us.example.com:443?security=tls&sni=us.example.com#US-LA-01';
let oparse = parse_link(olink);
let oid = node_fingerprint(oparse.outbound);
check(oid == lc(oid), 'node ids are lowercase');
check(override_key('ABCD12') == 'abcd12', 'override_key lowercases ids');

/* full identity: same server/uuid/port but different ws path must not dedupe */
let ws1 = parse_link('vmess://eyJhZGQiOiAiZXhhbXBsZS5jb20iLCAicG9ydCI6ICI0NDMiLCAiaWQiOiAiVVVJRCIsICJuZXQiOiAid3MiLCAicGF0aCI6ICIvd3MxIiwgInRscyI6ICJ0bHMiLCAicHMiOiAiQSJ9');
let ws2 = parse_link('vmess://eyJhZGQiOiAiZXhhbXBsZS5jb20iLCAicG9ydCI6ICI0NDMiLCAiaWQiOiAiVVVJRCIsICJuZXQiOiAid3MiLCAicGF0aCI6ICIvd3MyIiwgInRscyI6ICJ0bHMiLCAicHMiOiAiQiJ9');
check(ws1.ok && ws2.ok && node_fingerprint(ws1.outbound) != node_fingerprint(ws2.outbound), 'transport differences change fingerprint');
let wsDup = parse_link('vmess://eyJhZGQiOiAiZXhhbXBsZS5jb20iLCAicG9ydCI6ICI0NDMiLCAiaWQiOiAiVVVJRCIsICJuZXQiOiAid3MiLCAicGF0aCI6ICIvd3MxIiwgInRscyI6ICJ0bHMiLCAicHMiOiAiQSJ9');
check(node_fingerprint(ws1.outbound) == node_fingerprint(wsDup.outbound), 'identical nodes keep same fingerprint');

mkdir_p(PATH.meta_dir);
write_json(PATH.meta_dir + '/ovtest.json', { nodes: [ { name: 'US-LA-01', type: oparse.type, server: oparse.server, server_port: oparse.server_port, outbound: oparse.outbound } ] });

function collect(ovs) {
	let cfg = {
		egress: { native_keywords: '原生,native' }, nodes: [], node_overrides: ovs || [],
		subscriptions: [ { '.name': 'ovtest', name: 'S', enabled: '1' } ]
	};
	return collect_nodes(cfg);
}
function groups_of(col) {
	let g = group_nodes(col.nodes);
	return sprintf('auto=%d native=%d us=%d', length(g.auto), length(g.native), length(g.us));
}
check(groups_of(collect([])) == 'auto=1 native=0 us=1', 'override: no override keeps node in auto+us');
check(groups_of(collect([ { '.name': 'ov_a', id: oid, native_mode: '1' } ])) == 'auto=0 native=1 us=0', 'override: native_mode=1 moves node to native group');
check(groups_of(collect([ { '.name': 'ov_a', id: uc(oid), native_mode: '1' } ])) == 'auto=0 native=1 us=0', 'override: id matched case-insensitively');
check(groups_of(collect([ { '.name': 'ov_a', id: oid, native_mode: '0' } ])) == 'auto=1 native=0 us=1', 'override: native_mode=0 stays non-native');
check(groups_of(collect([ { '.name': 'ov_a', id: oid, native_mode: 'auto' } ])) == 'auto=1 native=0 us=1', 'override: native_mode=auto uses keywords');
check(groups_of(collect([ { '.name': 'ov_a', id: oid, enabled: '0' } ])) == 'auto=0 native=0 us=0', 'override: enabled=0 drops node');
/* old UCI written before the 2026-11-15 fingerprint change keeps working via legacy id */
check(groups_of(collect([ { '.name': 'ov_legacy', id: legacy_fingerprint(oparse.outbound), native_mode: '1' } ])) == 'auto=0 native=1 us=0', 'override: legacy id still matches');

/* generator */
function mknode(link, country, native) {
	let p = parse_link(link);
	let id = node_fingerprint(p.outbound);
	return { id: id, tag: node_tag(p.name, id), name: p.name, type: p.type, server: p.server, server_port: p.server_port,
		outbound: p.outbound, source: 'test', source_name: 'test', country: country, country_mode: 'auto', native: native, native_mode: native ? '1' : 'auto' };
}
let nodes = [
	mknode('vless://11111111-1111-1111-1111-111111111111@us.example.com:443?security=tls&sni=us.example.com#US-01', 'us', false),
	mknode('trojan://pw@jp.example.com:443?sni=jp.example.com#JP-01', 'jp', false),
	mknode('hysteria2://pw@hk.example.com:443?sni=hk.example.com#HK-01', 'hk', false),
	mknode('vless://11111111-1111-1111-1111-111111111111@native.example.com:443?security=reality&sni=native.example.com&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=01#原生-01', 'us', true)
];
let cfg = {
	main: { log_level: 'info' }, inbound: { address: '172.19.0.1/30,fdfe:dcba:9876::1/126', mtu: '9000', strict_route: '0', exclude_cn: '1' },
	dns: { mode: 'split', strategy: 'prefer_ipv4' },
	egress: { auto_url: 'https://www.gstatic.com/generate_204', auto_interval: '10m', auto_tolerance: '50', default_group: 'auto', native_keywords: '原生,native' },
	rulesets: [ { '.name': 'rs_custom_1', kind: 'custom', name: 'Custom', type: 'inline', domains: 'example.com\n1.2.3.0/24', target: 'us', enabled: '1', order: '10' } ],
	egress_groups: [ { '.name': 'eg_test', name: 'Test', type: 'selector', members: [ nodes[0].id, nodes[1].id ], default_node: nodes[0].id, enabled: '1' } ],
	subscriptions: [], nodes: [], node_overrides: []
};
let gen = build_config(cfg, { nodes: nodes, warnings: [] });
check(gen.ok, 'generator builds config');
if (gen.ok) {
	let tags = {};
	for (let o in gen.config.outbounds) tags[o.tag] = true;
	check(tags['direct'] && tags['auto'] && tags['us'] && tags['jp'] && tags['hk'] && tags['native'] && tags['default'], 'built-in egress groups generated');
	check(tags['eg_test'], 'custom egress group generated');
	let autoOut = null;
	for (let o in gen.config.outbounds) if (o.tag == 'auto') autoOut = o;
	check(autoOut != null && index(autoOut.outbounds, nodes[3].tag) < 0, 'native node excluded from auto');
	let tun = gen.config.inbounds[0];
	check(length(gen.config.inbounds) == 1 && tun.type == 'tun' && tun.tag == 'tun-in', 'generator emits a single tun inbound');
	check(tun.auto_route == true && tun.auto_redirect == true, 'tun enables auto_route and auto_redirect');
	check(tun.dns_mode == 'hijack', 'tun hijacks DNS');
	check(tun.listen == null && tun.listen_port == null, 'mixed listen fields removed');
	check(index(tun.route_exclude_address_set || [], 'rs_builtin_cn_1') >= 0, 'CN geoip rule set excluded from tun routes');
	check(gen.config.dns.servers[0].type == 'udp' && gen.config.dns.servers[0].detour == 'direct-dns', 'direct DNS bypasses the proxy detour');
	check(gen.config.dns.servers[1].tls && gen.config.dns.servers[1].tls.server_name == 'cloudflare-dns.com', 'proxy DoH sets tls server_name');
	let route = gen.config.route.rules;
	check(route[3].domain_suffix && route[3].outbound == 'us', 'custom rule before built-ins');
	check(route[length(route) - 1].rule_set && route[length(route) - 1].outbound == 'default', 'built-in fallback target');
	let dnsDirect = null;
	for (let o in gen.config.outbounds) if (o.tag == 'direct-dns') dnsDirect = o;
	check(dnsDirect != null && dnsDirect.tcp_fast_open === true, 'direct DNS detour target is not an empty direct outbound');
	cfg.inbound.exclude_cn = '0';
	let genNoExclude = build_config(cfg, { nodes: nodes, warnings: [] });
	check(genNoExclude.ok && !genNoExclude.config.inbounds[0].route_exclude_address_set, 'exclude_cn=0 disables the CN pre-match exclusion');
	cfg.inbound.exclude_cn = '1';

	/* custom egress group: tag must equal the UCI section name LuCI stores as target */
	let customCfg = {
		main: { log_level: 'info' },
		inbound: { address: '172.19.0.1/30,fdfe:dcba:9876::1/126', mtu: '9000', strict_route: '0', exclude_cn: '1' },
		dns: { mode: 'split', strategy: 'prefer_ipv4' },
		egress: { auto_url: 'https://www.gstatic.com/generate_204', auto_interval: '10m', auto_tolerance: '50', default_group: 'auto', native_keywords: '原生,native' },
		rulesets: [ { '.name': 'rs_custom_target', kind: 'custom', name: 'Target test', type: 'inline', domains: 'target.example', target: 'new1a2b3c', enabled: '1', order: '10' } ],
		egress_groups: [ { '.name': 'new1a2b3c', name: 'LuCI group', type: 'selector', members: [ nodes[0].id ], default_node: nodes[0].id, enabled: '1' } ],
		subscriptions: [], nodes: [], node_overrides: []
	};
	let cgen = build_config(customCfg, { nodes: nodes, warnings: [] });
	check(cgen.ok, 'custom egress target builds');
	let customTag = false, customTarget = false;
	if (cgen.ok) {
		for (let o in cgen.config.outbounds) if (o.tag == 'new1a2b3c') customTag = true;
		for (let rr in cgen.config.route.rules) if (rr.outbound == 'new1a2b3c') customTarget = true;
	}
	check(customTag && customTarget, 'custom egress tag matches UCI section target');
}

/* tailscale endpoint (sing-box 1.14, gVisor build) */
function ts_base(ts) {
	return {
		main: { log_level: 'info' },
		inbound: { address: '172.19.0.1/30,fdfe:dcba:9876::1/126', mtu: '9000', strict_route: '0', exclude_cn: '1' },
		dns: { mode: 'split', strategy: 'prefer_ipv4' },
		egress: { default_group: 'auto' },
		tailscale: ts || {},
		rulesets: [], egress_groups: [], subscriptions: [], nodes: [], node_overrides: []
	};
}
let tsOff = build_config(ts_base({ enabled: '0', auth_key: 'tskey-auth-x' }), { nodes: nodes, warnings: [] });
check(tsOff.ok && tsOff.config.endpoints == null, 'tailscale disabled emits no endpoints');
let tsOffDns = false;
for (let ds in tsOff.config.dns.servers) if (ds.type == 'tailscale') tsOffDns = true;
check(!tsOffDns, 'tailscale disabled emits no tailscale DNS server');

let tsOn = build_config(ts_base({
	enabled: '1', auth_key: 'tskey-auth-abc', hostname: 'openwrt-router',
	accept_routes: '1', advertise_routes: '192.168.1.0/24, 10.10.0.0/16',
	advertise_exit_node: '1'
}), { nodes: nodes, warnings: [] });
check(tsOn.ok && length(tsOn.config.endpoints) == 1, 'tailscale enabled emits one endpoint');
if (tsOn.ok) {
	let ep = tsOn.config.endpoints[0];
	check(ep.type == 'tailscale' && ep.tag == 'ts-ep', 'tailscale endpoint type/tag');
	check(ep.state_directory == PATH.etc + '/tailscale', 'tailscale default state directory');
	check(ep.domain_resolver == 'dns-direct' && ep.detour == 'direct-dns', 'tailscale control traffic bypasses the proxy');
	check(ep.auth_key == 'tskey-auth-abc' && ep.hostname == 'openwrt-router', 'tailscale auth key and hostname');
	check(ep.accept_routes === true && length(ep.advertise_routes) == 2 && ep.advertise_routes[1] == '10.10.0.0/16', 'tailscale accept/advertise routes');
	check(ep.advertise_exit_node === true, 'tailscale advertise exit node');
	let route = tsOn.config.route.rules;
	let preferred = -1, privateRule = -1;
	for (let i = 0; i < length(route); i++) {
		if (route[i].preferred_by && route[i].preferred_by[0] == 'ts-ep') preferred = i;
		if (route[i].ip_is_private) privateRule = i;
	}
	check(preferred >= 0 && privateRule >= 0 && preferred < privateRule, 'tailnet rule precedes private-IP direct rule');
	check(tsOn.config.route.final == 'default', 'default egress stays the proxy unless an exit node is the default');
	let tsDns = null;
	for (let ds in tsOn.config.dns.servers) if (ds.type == 'tailscale') tsDns = ds;
	check(tsDns != null && tsDns.tag == 'dns-ts' && tsDns.endpoint == 'ts-ep' && tsDns.accept_default_resolvers === true, 'tailscale DNS server references the endpoint');
	check(tsOn.config.dns.rules[0].preferred_by && tsOn.config.dns.rules[0].server == 'dns-ts', 'MagicDNS rule first in DNS rules');
}

let tsExit = build_config(ts_base({
	enabled: '1', auth_key: 'k', exit_node: 'vps-exit', exit_node_allow_lan_access: '1', exit_node_default: '1'
}), { nodes: nodes, warnings: [] });
check(tsExit.ok && tsExit.config.endpoints[0].exit_node == 'vps-exit' && tsExit.config.endpoints[0].exit_node_allow_lan_access === true, 'tailscale exit node and LAN access');
check(tsExit.ok && tsExit.config.route.final == 'ts-ep', 'default egress can be the tailscale exit node');

let tsExitNoNode = build_config(ts_base({ enabled: '1', auth_key: 'k', exit_node_default: '1' }), { nodes: nodes, warnings: [] });
check(tsExitNoNode.ok && tsExitNoNode.config.route.final == 'default', 'exit-node default without a node is ignored');
check(index(join('\n', tsExitNoNode.warnings), '已忽略') >= 0, 'ignored exit-node default is reported');

let tsNoKey = build_config(ts_base({ enabled: '1' }), { nodes: nodes, warnings: [] });
check(tsNoKey.ok && tsNoKey.config.endpoints[0].auth_key == null, 'tailscale without auth_key omits the field');
check(index(join('\n', tsNoKey.warnings), 'auth_key') >= 0, 'tailscale without auth_key warns about interactive login');

let tsBadRoute = build_config(ts_base({ enabled: '1', auth_key: 'k', advertise_routes: '0.0.0.0/0' }), { nodes: nodes, warnings: [] });
check(!tsBadRoute.ok && index(join('\n', tsBadRoute.errors), 'advertise_exit_node') >= 0, 'default route in advertise_routes rejected');
let tsBadCidr = build_config(ts_base({ enabled: '1', auth_key: 'k', advertise_routes: 'not-a-cidr' }), { nodes: nodes, warnings: [] });
check(!tsBadCidr.ok && index(join('\n', tsBadCidr.errors), 'not-a-cidr') >= 0, 'invalid advertise route rejected');

let tsRel = build_config(ts_base({ enabled: '1', auth_key: 'k', state_directory: 'ts-state' }), { nodes: nodes, warnings: [] });
check(tsRel.ok && tsRel.config.endpoints[0].state_directory == PATH.etc + '/ts-state', 'relative state directory resolves under etc');

let tsProxyDns = ts_base({ enabled: '1', auth_key: 'k' });
tsProxyDns.dns.mode = 'proxy';
let tsProxy = build_config(tsProxyDns, { nodes: nodes, warnings: [] });
check(tsProxy.ok && length(tsProxy.config.dns.rules) == 1 && tsProxy.config.dns.rules[0].preferred_by, 'proxy DNS mode keeps the MagicDNS rule');

let tsSystemCfg = ts_base({ enabled: '1', auth_key: 'k' });
tsSystemCfg.dns.mode = 'system';
let tsSystem = build_config(tsSystemCfg, { nodes: nodes, warnings: [] });
let tsSystemDns = false;
for (let ds in tsSystem.config.dns.servers) if (ds.type == 'tailscale') tsSystemDns = true;
check(tsSystem.ok && !tsSystemDns && length(tsSystem.config.dns.rules) == 0, 'system DNS mode omits the tailscale DNS server');
check(index(join('\n', tsSystem.warnings), 'MagicDNS') >= 0, 'system DNS mode warns about MagicDNS');

/* rule set resolution */
let rcfg = { rulesets: [], egress_groups: [] };
let rr = resolve_rulesets(rcfg);
check(length(rr.errors) == 0 && length(rr.rules) == 6, 'six built-in rule sets resolve from bundle');
check(rr.rules[0].target == 'direct', 'built-in CN target direct');
let cnAiDomains = rr.rules[0].inline.domain_suffix || [];
check(index(cnAiDomains, 'deepseek.com') >= 0 && index(cnAiDomains, 'moonshot.cn') >= 0, 'CN AI rule set keeps parent domains');
check(index(cnAiDomains, 'chat.deepseek.com') < 0 && index(cnAiDomains, 'kimi.moonshot.cn') < 0, 'CN AI rule set drops subdomains covered by parents');

/* core helpers */
check(arch_asset('x86_64') == 'amd64-musl', 'arch x86_64');
check(arch_asset('aarch64_cortex-a53') == 'arm64-musl', 'arch aarch64');
check(version_ge('1.14.4', '1.14.4') && !version_ge('1.13.21', '1.14.4'), 'version comparison');

/* regression: config migration for newer cores only removes fields the target version dropped */
function migrate_fixture() {
	return {
		log: { level: 'info' },
		experimental: {
			cache_file: { enabled: true, store_rdrc: true, rdrc_timeout: '1m', store_dns: true, path: '/tmp/singbox-cache.db' }
		},
		dns: {
			servers: [ { type: 'udp', server: '1.1.1.1', tag: 'dns-direct' } ],
			rules: [
				{ domain_suffix: [ '.example.com' ], server: 'dns-direct', strategy: 'prefer_ipv4' },
				{ domain: [ 'only.example.net' ], server: 'dns-proxy' }
			]
		},
		inbounds: [ { type: 'tun', tag: 'tun-in', stack: 'system', auto_route: true } ],
		outbounds: [ { type: 'direct', tag: 'direct' } ]
	};
}
let mig115Cfg = migrate_fixture();
let mig115Before = sprintf('%J', mig115Cfg);
let mig115 = migrate_config_for_core(mig115Cfg, '1.15.0');
check(length(mig115.changes) == 0 && sprintf('%J', mig115.config) == mig115Before, 'core migration leaves config untouched on 1.15');
let mig16Cfg = migrate_fixture();
let mig16 = migrate_config_for_core(mig16Cfg, '1.16.0');
let mig16Cache = mig16.config.experimental.cache_file;
check(length(mig16.changes) == 3, 'core migration reports three 1.16 changes');
check(mig16Cache.rdrc_timeout == null && mig16Cache.store_rdrc == null, 'core migration drops 1.16 cache rdrc fields');
check(mig16.config.dns.rules[0].strategy == null && mig16.config.dns.rules[0].server == 'dns-direct', 'core migration drops dns rule strategy only');
check(mig16.config.inbounds[0].stack == 'system', 'core migration keeps tun stack on 1.16');
check(mig16Cache.enabled == true && mig16Cache.store_dns == true && mig16Cache.path == '/tmp/singbox-cache.db', 'core migration keeps neighbouring cache fields');
check(mig16.config.dns.rules[1].server == 'dns-proxy' && length(mig16.config.dns.rules) == 2, 'core migration keeps neighbouring dns rules');
let mig17Cfg = migrate_fixture();
let mig17 = migrate_config_for_core(mig17Cfg, '1.17.0');
check(mig17.config.inbounds[0].stack == null, 'core migration drops tun stack on 1.17');
check(mig17.config.experimental.cache_file.rdrc_timeout == null && mig17.config.dns.rules[0].strategy == null, 'core migration applies 1.16 rules on 1.17');
check(length(mig17.changes) == 4, 'core migration reports four changes on 1.17');
check(mig17.config.inbounds[0].auto_route == true && length(mig17.config.inbounds) == 1, 'core migration keeps tun neighbours on 1.17');
let plainCfg = { log: { level: 'info' }, experimental: { cache_file: { enabled: true } }, dns: { servers: [] }, inbounds: [ { type: 'tun', tag: 'tun-in' } ] };
let plainBefore = sprintf('%J', plainCfg);
let migPlain = migrate_config_for_core(plainCfg, '1.17.0');
check(length(migPlain.changes) == 0 && sprintf('%J', migPlain.config) == plainBefore, 'core migration no-op without legacy fields');
let migNoVersion = migrate_config_for_core(migrate_fixture(), '');
check(length(migNoVersion.changes) == 0, 'core migration no-op without target version');
let migNull = migrate_config_for_core(null, '1.17.0');
check(length(migNull.changes) == 0 && migNull.config == null, 'core migration tolerates non-object config');

/* release listing and plugin version helpers */
let releases = parse_tags('[{"tag_name":"v1.14.4","draft":false,"prerelease":false},{"tag_name":"v1.15.0-alpha.1","prerelease":true},{"tag_name":"v1.14.4"},{"tag_name":""}]', 10);
check(length(releases) == 1 && releases[0] == 'v1.14.4', 'release tags skip prerelease and duplicates');
check(length(parse_tags('not json', 10)) == 0, 'invalid release JSON yields no tags');
check(join(',', parse_release_page('<a href="/x/releases/tag/v1.2.3">a</a><a href="/x/releases/tag/v1.2.3">b</a><a href="/x/releases/tag/v1.2.2">c</a>', 10)) == 'v1.2.3,v1.2.2', 'release page HTML fallback parse');
check(mirror_url('https://api.github.com/repos/x/y', 'https://ghfast.top') == 'https://ghfast.top/https://api.github.com/repos/x/y', 'mirror prefix normalization');
check(asset_name('x86_64') == 'singbox-lite-x86_64-openwrt-25.12.tar.gz', 'plugin asset name');
check(asset_name('aarch64_cortex-a53') == 'singbox-lite-aarch64_cortex-a53-openwrt-25.12.tar.gz', 'plugin asset name arm64');
let dl = download_url('0.2.0', 'x86_64', 'https://ghfast.top/');
check(dl.tag == 'v0.2.0' && match(dl.url, /^https:\/\/ghfast\.top\/https:\/\/github\.com\/hugeww\/singbox-lite\/releases\/download\/v0\.2\.0\/singbox-lite-x86_64-openwrt-25\.12\.tar\.gz$/) != null, 'plugin download URL honours mirror');
check(base_version('0.1.0-r1') == '0.1.0' && base_version('v0.2.0') == '0.2.0', 'package version base');
check(parse_apk_list('luci-app-singbox-lite-0.1.0-r1 x86_64 {luci-app-singbox-lite} (GPL-3.0-or-later)', 'luci-app-singbox-lite') == '0.1.0-r1', 'apk list version parse');
check(parse_apk_db('C:abc\nP:luci-app-singbox-lite\nV:0.1.0-r1\n\nP:other\nV:9', 'luci-app-singbox-lite') == '0.1.0-r1', 'apk db version parse');

/* LuCI panel helpers */
check(pct('US 01/东京') == 'US%2001%2F%E4%B8%9C%E4%BA%AC', 'panel percent encoding');
let pc = panel_config({ panel: { enabled: '1', listen: '', port: '0', secret: ' s ' } });
check(pc.enabled && pc.listen == '127.0.0.1' && pc.port == 9090 && pc.secret == 's', 'panel config defaults');
let pdata = { proxies: {
	default: { type: 'selector', now: 'a', all: [ 'a', 'b' ] },
	a: { type: 'vless', history: [ { delay: 120 } ] },
	b: { type: 'trojan' }
} };
let pg = proxy_groups(pdata);
check(length(pg) == 1 && pg[0].now == 'a' && length(pg[0].members) == 2, 'panel proxy group parse');
check(pg[0].members[0].delay == 120 && pg[0].members[1].delay == 0, 'panel member delay');
let cl = connection_list({ downloadTotal: 1024, uploadTotal: 512, connections: [
	{ id: 'x', metadata: { host: 'a.com', network: 'tcp', destinationPort: 443 }, chains: [ 'default', 'a' ], upload: 10, download: 20 }
] }, 10);
check(cl.download == 1024 && cl.upload == 512 && length(cl.connections) == 1, 'panel connection summary');
check(cl.connections[0].chains[1] == 'a' && cl.connections[0].upload == 10, 'panel connection fields');

/* official dashboard + clash_api generation */
check(dashboard_archive_url('') == 'https://github.com/SagerNet/sing-box-dashboard/archive/refs/heads/gh-pages.zip', 'dashboard archive URL');
check(dashboard_archive_url('https://ghfast.top/') == 'https://ghfast.top/https://github.com/SagerNet/sing-box-dashboard/archive/refs/heads/gh-pages.zip', 'dashboard archive URL honours mirror');
check(dashboard_selected({ panel: { dashboard: 'official' } }) == 'official' && dashboard_selected({}) == 'native', 'dashboard selection');
let panelCfg = {
	main: { log_level: 'info' }, inbound: { listen: '127.0.0.1', port: '7890', auth: '0' },
	dns: { mode: 'split', strategy: 'prefer_ipv4' },
	egress: { default_group: 'auto' },
	panel: { enabled: '1', listen: '0.0.0.0', port: '9090', secret: 'sekret', dashboard: 'native' },
	rulesets: [], egress_groups: [], subscriptions: [], nodes: [], node_overrides: []
};
let pgen = build_config(panelCfg, { nodes: nodes, warnings: [] });
check(pgen.ok && pgen.config.experimental.clash_api.external_controller == '0.0.0.0:9090' && pgen.config.experimental.clash_api.secret == 'sekret', 'generator emits clash_api');
let pgenOff = build_config({ main: {}, inbound: {}, dns: { mode: 'split' }, egress: {}, panel: { enabled: '0' }, rulesets: [], egress_groups: [], subscriptions: [], nodes: [], node_overrides: [] }, { nodes: nodes, warnings: [] });
check(pgenOff.ok && pgenOff.config.experimental.clash_api == null, 'clash_api omitted when panel disabled');
let pgenV6 = build_config({
	main: {}, inbound: {}, dns: { mode: 'split' }, egress: {},
	panel: { enabled: '1', listen: '::', port: '9090', secret: 'sekret', dashboard: 'native' },
	rulesets: [], egress_groups: [], subscriptions: [], nodes: [], node_overrides: []
}, { nodes: nodes, warnings: [] });
check(pgenV6.ok && pgenV6.config.experimental.clash_api.external_controller == '[::]:9090', 'IPv6 clash_api controller is bracketed');

/* Official dashboard is served by the sing-box API service, not Clash API */
let officialCfg = {
	main: {}, inbound: {}, dns: { mode: 'split' }, egress: {},
	panel: { enabled: '1', listen: '0.0.0.0', port: '9090', secret: 'sekret', dashboard: 'official' },
	rulesets: [], egress_groups: [], subscriptions: [], nodes: [], node_overrides: []
};
let ogen = build_config(officialCfg, { nodes: nodes, warnings: [] });
check(ogen.ok && ogen.config.experimental.clash_api == null, 'official dashboard omits clash_api');
check(length(ogen.config.services || []) == 1 && ogen.config.services[0].type == 'api' &&
	ogen.config.services[0].listen == '0.0.0.0' && ogen.config.services[0].listen_port == 9090 &&
	ogen.config.services[0].secret == 'sekret', 'official dashboard uses sing-box api service');
let ost = panel_status(officialCfg);
check(ost.ok && ost.dashboard == 'official' && ost.port == 9090, 'official panel status does not probe Clash API');

if (failures) {
	printf('FAILED: %d\n', failures);
	exit(1);
}
printf('ALL TESTS PASSED\n');
