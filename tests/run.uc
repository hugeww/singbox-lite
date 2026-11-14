'use strict';

import { readfile } from 'fs';
import { parse_link, parse_manual_input, clash_to_outbound } from 'sbx_links';
import { parse_body } from 'sbx_subs';
import { classify_country, is_native, node_fingerprint } from 'sbx_nodes';
import { build_config } from 'sbx_generator';
import { resolve_rulesets } from 'sbx_rulesets';
import { arch_asset, version_ge } from 'sbx_core';
import { parse_tags, parse_release_page, mirror_url } from 'sbx_releases';
import { asset_name, download_url, base_version, parse_apk_list, parse_apk_db } from 'sbx_plugin';
import { pct, proxy_groups, connection_list, panel_config, last_delay } from 'sbx_panel';
import { PATH } from 'sbx_common';

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

/* subscription formats */
let base = parse_body(fixture('base64-sub.txt'), 'auto');
check(base.ok && length(base.nodes) == 6, 'base64 subscription');
let plain = parse_body(fixture('plain-links.txt'), 'auto');
check(plain.ok && length(plain.nodes) == 6, 'plain URI subscription');
let jsonSub = parse_body(fixture('singbox-sub.json'), 'auto');
check(jsonSub.ok && length(jsonSub.nodes) == 1, 'sing-box JSON subscription');
let html = parse_body(fixture('bad.html'), 'auto');
check(!html.ok, 'HTML subscription rejected');

/* node classification */
let egress = { us_keywords: '美国,US,USA', jp_keywords: '日本,JP', hk_keywords: '香港,HK', native_keywords: '原生,原生IP,native' };
check(classify_country('🇺🇸 美国 洛杉矶 01', egress) == 'us', 'US country classification');
check(classify_country('日本 东京 01', egress) == 'jp', 'JP country classification');
check(classify_country('HK-01', egress) == 'hk', 'HK country classification');
check(classify_country('Singapore', egress) == 'other', 'other country classification');
check(is_native('原生 IP 01', egress), 'native keyword');
check(!is_native('normal 01', egress), 'non-native keyword');

/* generator */
function mknode(link, country, native) {
	let p = parse_link(link);
	let id = node_fingerprint(p.outbound);
	return { id: id, tag: 'node_' + id, name: p.name, type: p.type, server: p.server, server_port: p.server_port,
		outbound: p.outbound, source: 'test', source_name: 'test', country: country, country_mode: 'auto', native: native, native_mode: native ? '1' : 'auto' };
}
let nodes = [
	mknode('vless://11111111-1111-1111-1111-111111111111@us.example.com:443?security=tls&sni=us.example.com#US-01', 'us', false),
	mknode('trojan://pw@jp.example.com:443?sni=jp.example.com#JP-01', 'jp', false),
	mknode('hysteria2://pw@hk.example.com:443?sni=hk.example.com#HK-01', 'hk', false),
	mknode('vless://11111111-1111-1111-1111-111111111111@native.example.com:443?security=reality&sni=native.example.com&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=01#原生-01', 'us', true)
];
let cfg = {
	main: { log_level: 'info' }, inbound: { listen: '127.0.0.1', port: '7890', auth: '0' },
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
	check(autoOut != null && index(autoOut.outbounds, 'node_' + nodes[3].id) < 0, 'native node excluded from auto');
	let route = gen.config.route.rules;
	check(route[2].domain_suffix && route[2].outbound == 'us', 'custom rule before built-ins');
	check(route[length(route) - 1].rule_set && route[length(route) - 1].outbound == 'default', 'built-in fallback target');
}

/* rule set resolution */
let rcfg = { rulesets: [], egress_groups: [] };
let rr = resolve_rulesets(rcfg);
check(length(rr.errors) == 0 && length(rr.rules) == 6, 'six built-in rule sets resolve from bundle');
check(rr.rules[0].target == 'direct', 'built-in CN target direct');

/* core helpers */
check(arch_asset('x86_64') == 'amd64-musl', 'arch x86_64');
check(arch_asset('aarch64_cortex-a53') == 'arm64-musl', 'arch aarch64');
check(version_ge('1.14.4', '1.14.4') && !version_ge('1.13.21', '1.14.4'), 'version comparison');

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

if (failures) {
	printf('FAILED: %d\n', failures);
	exit(1);
}
printf('ALL TESTS PASSED\n');
