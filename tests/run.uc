'use strict';

import { readfile } from 'fs';
import { parse_link, parse_manual_input, clash_to_outbound } from 'sbx_links';
import { parse_body } from 'sbx_subs';
import { classify_country, is_native, node_fingerprint } from 'sbx_nodes';
import { build_config } from 'sbx_generator';
import { resolve_rulesets } from 'sbx_rulesets';
import { arch_asset, version_ge } from 'sbx_core';
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

if (failures) {
	printf('FAILED: %d\n', failures);
	exit(1);
}
printf('ALL TESTS PASSED\n');
