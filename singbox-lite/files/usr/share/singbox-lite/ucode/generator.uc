'use strict';

import { trim, split_csv, file_exists, PATH } from 'sbx_common';
import { group_nodes, find_node } from 'sbx_nodes';
import { resolve_rulesets } from 'sbx_rulesets';

function tag_slug(s) {
	s = lc(trim(s == null ? '' : s));
	s = replace(s, /[^a-z0-9_-]+/g, '_');
	s = replace(s, /^_+|_+$/g, '');
	return length(s) ? substr(s, 0, 32) : 'x';
}

function as_list(v) {
	if (v == null) return [];
	if (type(v) == 'array') return v;
	return split_csv(v);
}

function node_outbound(n) {
	let out = {};
	for (let k in keys(n.outbound)) out[k] = n.outbound[k];
	out.tag = n.tag;
	return out;
}

function make_selector(tag, members, default_tag) {
	let tags = [];
	for (let n in members) push(tags, n.tag);
	if (!length(tags)) return null;
	let def = default_tag && index(tags, default_tag) >= 0 ? default_tag : tags[0];
	return { type: 'selector', tag: tag, outbounds: tags, default: def };
}

function make_urltest(tag, members, url, interval, tolerance) {
	let tags = [];
	for (let n in members) push(tags, n.tag);
	if (!length(tags)) return null;
	return {
		type: 'urltest', tag: tag, outbounds: tags,
		url: url || 'https://www.gstatic.com/generate_204',
		interval: interval || '10m',
		tolerance: int(tolerance || 50)
	};
}

function default_node_tag(members, id) {
	if (length(id || '')) {
		for (let n in members)
			if (n.id == id || n.legacy_id == id || n.fingerprint == id) return n.tag;
	}
	return length(members) ? members[0].tag : null;
}

/* Tags reserved by the generator's built-in groups. */
const RESERVED_GROUP_TAGS = {
	direct: true, default: true, auto: true, native: true, us: true, jp: true, hk: true, other: true
};

/*
 * 自定义出口组 tag 契约（与 luci-app-singbox-lite 的 rulesets.js 共用）：
 * 规则集的 target 里存的就是 egress_group 的 UCI section 名（LuCI 新建 section
 * 的 id 形如 new%06x，例如 new1a2b3c），所以生成器必须原样使用 section 名作为
 * outbound tag，不能再加 eg_ 前缀或做 slug 归一化，否则 target 永远匹配不上。
 * 历史数据里本来就叫 eg_* 的 section 会原样保留。只有当 section 名为空、与保留
 * tag 冲突或与其它 tag 重复时，才退回 eg_<slug> 并输出 warning，绝不静默产生重复 tag。
 */
function custom_group_plans(cfg, nodes) {
	let entries = [];
	let wanted = {};
	for (let g in cfg.egress_groups || []) {
		if (g.enabled == '0') continue;
		let section = g['.name'] == null ? '' : g['.name'];
		push(entries, { group: g, section: section });
		if (length(section) && !RESERVED_GROUP_TAGS[section]) wanted[section] = true;
	}
	let used = {};
	for (let n in nodes || []) used[n.tag] = true;
	let plans = [];
	for (let e in entries) {
		let tag = e.section;
		let warning = null;
		if (!length(tag) || RESERVED_GROUP_TAGS[tag] || used[tag]) {
			let base = 'eg_' + tag_slug(e.section);
			tag = base;
			let n = 2;
			while (used[tag] || wanted[tag]) tag = base + '_' + (n++);
			warning = sprintf('自定义出口组 %s 的 section 名「%s」不可直接用作 tag，已改用 %s',
				e.group.name || e.section || '(空)', length(e.section) ? e.section : '(空)', tag);
		}
		used[tag] = true;
		push(plans, { group: e.group, tag: tag, warning: warning });
	}
	return plans;
}

/* Clash API 监听地址：IPv6 字面量必须加方括号（:: -> [::]:9090、::1 -> [::1]:9090）。 */
function listen_address(listen, port) {
	let host = listen == null ? '' : listen;
	if (match(host, /^\[.*\]$/)) host = substr(host, 1, length(host) - 2);
	if (match(host, /:/)) return '[' + host + ']:' + port;
	return host + ':' + port;
}

/*
 * Tailscale endpoint (sing-box 1.14, requires a with_gvisor/with_tailscale
 * build). The tag is shared by the endpoint, the ts DNS server and the
 * preferred_by rules, so keep it unlikely to collide with node/custom-group
 * tags (those are slug-hash or UCI section names).
 */
const TAILSCALE_TAG = 'ts-ep';
const TAILSCALE_DNS_TAG = 'dns-ts';

function tailscale_state_directory(value) {
	let dir = trim(value == null ? '' : value);
	if (!length(dir)) dir = PATH.etc + '/tailscale';
	if (!match(dir, /^\//)) dir = PATH.etc + '/' + dir;
	return dir;
}

function tailscale_routes(value, errors) {
	let routes = [];
	for (let item in as_list(value)) {
		let route = trim(item);
		if (!length(route)) continue;
		if (route == '0.0.0.0/0' || route == '::/0') {
			push(errors, 'Tailscale 的 advertise_routes 不能包含默认路由 0.0.0.0/0 或 ::/0，请改用 advertise_exit_node');
			continue;
		}
		if (!match(route, /^[0-9a-fA-F:.]+\/[0-9]{1,3}$/)) {
			push(errors, sprintf('Tailscale advertise_routes 条目「%s」不是合法 CIDR', route));
			continue;
		}
		push(routes, route);
	}
	return routes;
}

function tailscale_plan(cfg, warnings, errors) {
	let ts = cfg.tailscale || {};
	if (ts.enabled != '1') return { enabled: false };
	let auth_key = trim(ts.auth_key || '');
	let hostname = trim(ts.hostname || '');
	let exit_node = trim(ts.exit_node || '');
	let endpoint = {
		type: 'tailscale',
		tag: TAILSCALE_TAG,
		state_directory: tailscale_state_directory(ts.state_directory),
		/* Control plane/DERP traffic must not depend on the selected proxy
		   group: resolve the control host directly and dial out directly. */
		domain_resolver: 'dns-direct',
		detour: 'direct-dns',
		accept_routes: ts.accept_routes == '1'
	};
	if (length(auth_key)) endpoint.auth_key = auth_key;
	else push(warnings, 'Tailscale 已启用但未填写 auth_key：首次启动后需要从日志中的登录链接完成认证');
	if (length(hostname)) endpoint.hostname = hostname;
	let advertise_routes = tailscale_routes(ts.advertise_routes, errors);
	if (length(advertise_routes)) endpoint.advertise_routes = advertise_routes;
	if (ts.advertise_exit_node == '1') endpoint.advertise_exit_node = true;
	if (length(exit_node)) {
		endpoint.exit_node = exit_node;
		if (ts.exit_node_allow_lan_access == '1') endpoint.exit_node_allow_lan_access = true;
	}
	let use_default = ts.exit_node_default == '1';
	if (use_default && !length(exit_node)) {
		push(warnings, 'Tailscale 未填写出口节点，已忽略「默认出口走 Tailscale」');
		use_default = false;
	}
	return { enabled: true, endpoint: endpoint, use_default: use_default };
}

function build_config(cfg, collected) {
	let warnings = [];
	let errors = [];
	let nodes = collected.nodes;
	let groups = group_nodes(nodes);

	if (!length(nodes)) push(errors, '没有可用节点：请先添加订阅或手动节点');

	let ts = tailscale_plan(cfg, warnings, errors);

	let egress = cfg.egress || {};
	let outbounds = [ { type: 'direct', tag: 'direct' }, { type: 'direct', tag: 'direct-dns', tcp_fast_open: true } ];
	let group_tags = { direct: true };

	/* auto */
	if (length(groups.auto)) {
		if (length(groups.auto) > 200) {
			push(warnings, '非原生节点超过 200 个，已跳过自动测速组');
		} else {
			let auto = make_urltest('auto', groups.auto, egress.auto_url, egress.auto_interval, egress.auto_tolerance);
			if (auto) { push(outbounds, auto); group_tags.auto = true; }
		}
	}

	/* country groups */
	for (let c in [ 'us', 'jp', 'hk', 'other' ]) {
		let members = groups[c];
		if (!length(members)) continue;
		let def = default_node_tag(members, egress[c + '_default']);
		let s = make_selector(c, members, def);
		if (s) { push(outbounds, s); group_tags[c] = true; }
	}

	/* native group, never auto/default */
	if (length(groups.native)) {
		let def = default_node_tag(groups.native, egress.native_default);
		let s = make_selector('native', groups.native, def);
		if (s) { push(outbounds, s); group_tags.native = true; }
	}

	/* default selector */
	let default_members = [];
	for (let tag in [ 'auto', 'us', 'jp', 'hk', 'other' ]) {
		for (let o in outbounds)
			if (o.tag == tag && o.type != 'direct') { push(default_members, o); break; }
	}
	if (length(default_members)) {
		let desired = egress.default_group || 'auto';
		let def = null;
		for (let o in default_members) if (o.tag == desired) { def = o.tag; break; }
		if (!def) def = default_members[0].tag;
		let tags = [];
		for (let o in default_members) push(tags, o.tag);
		push(outbounds, { type: 'selector', tag: 'default', outbounds: tags, default: def });
		group_tags.default = true;
	}

	/* custom egress groups: tag is the UCI section name verbatim (contract above) */
	let custom_groups = {};
	for (let p in custom_group_plans(cfg, nodes)) {
		let g = p.group;
		let tag = p.tag;
		if (p.warning) push(warnings, p.warning);
		let members = [];
		for (let id in as_list(g.members)) {
			let n = find_node(nodes, id);
			if (n) push(members, n);
		}
		if ((g.type || 'selector') == 'urltest') {
			let eligible = [];
			for (let n in members) if (!n.native) push(eligible, n);
			if (!length(eligible)) {
				push(warnings, sprintf('自定义出口组 %s 没有可用非原生节点，已跳过', g.name || tag));
				continue;
			}
			let u = make_urltest(tag, eligible, g.url || egress.auto_url, g.interval || egress.auto_interval, g.tolerance || egress.auto_tolerance);
			if (u) { push(outbounds, u); custom_groups[tag] = true; group_tags[tag] = true; }
		} else {
			if (!length(members)) {
				push(warnings, sprintf('自定义出口组 %s 没有成员，已跳过', g.name || tag));
				continue;
			}
			let def = default_node_tag(members, g.default_node);
			let s = make_selector(tag, members, def);
			if (s) { push(outbounds, s); custom_groups[tag] = true; group_tags[tag] = true; }
		}
	}

	/* node outbounds */
	for (let n in nodes) push(outbounds, node_outbound(n));

	/* rule sets and route rules */
	let resolved = resolve_rulesets(cfg);
	for (let e in resolved.errors) push(errors, e);
	let rule_set_defs = [];
	let dns_mode = cfg.dns && cfg.dns.mode ? cfg.dns.mode : 'split';
	let route_rules = [
		{ action: 'sniff' },
		{ protocol: 'dns', action: 'hijack-dns' }
	];
	/* Tailnet peers, MagicDNS names and accepted subnet routes must be routed
	   into the endpoint before the generic private-IP direct rule: accepted
	   routes are RFC1918 ranges and would otherwise leak out via 'direct'. */
	if (ts.enabled) push(route_rules, { preferred_by: [ TAILSCALE_TAG ], outbound: TAILSCALE_TAG });
	push(route_rules, { ip_is_private: true, outbound: 'direct' });
	let dns_rules = [];
	if (ts.enabled && dns_mode != 'system') push(dns_rules, { preferred_by: [ TAILSCALE_TAG ], server: TAILSCALE_DNS_TAG });
	if (dns_mode == 'split')
		push(dns_rules, { domain_suffix: [ '.lan', '.local', '.home.arpa' ], server: 'dns-direct' });
	let route_exclude_tags = [];
	let route_exclude_seen = {};

	for (let rule in resolved.rules) {
		let target = rule.target;
		if (!group_tags[target]) {
			push(errors, sprintf('规则集 %s 的目标出口组 %s 不存在或为空', rule.name, target));
			continue;
		}
		if (length(rule.files)) {
			let tags = [];
			let dns_tags = [];
			for (let f in rule.files) {
				push(rule_set_defs, { tag: f.tag, type: 'local', format: 'binary', path: f.path });
				push(tags, f.tag);
				/* GeoIP-only rule sets are intended for route address matching, not DNS rules. */
				if (!match(f.path, /\/geoip-[^\/]*$/))
					push(dns_tags, f.tag);
				/* The built-in CN rule is a full geoip-cn match; exclude it from TUN routes at the nftables layer. */
				if (rule.kind == 'builtin' && rule.source == 'builtin_cn' && rule.target == 'direct' &&
				    match(f.path, /\/geoip-cn\.srs$/) && !route_exclude_seen[f.tag]) {
					push(route_exclude_tags, f.tag);
					route_exclude_seen[f.tag] = true;
				}
			}
			push(route_rules, { rule_set: tags, outbound: target });
			if (length(dns_tags))
				push(dns_rules, { rule_set: dns_tags, server: target == 'direct' ? 'dns-direct' : 'dns-proxy' });
		}
		if (length(rule.inline.domain_suffix)) {
			push(route_rules, { domain_suffix: rule.inline.domain_suffix, outbound: target });
			push(dns_rules, { domain_suffix: rule.inline.domain_suffix, server: target == 'direct' ? 'dns-direct' : 'dns-proxy' });
		}
		if (length(rule.inline.ip_cidr))
			push(route_rules, { ip_cidr: rule.inline.ip_cidr, outbound: target });
		if (length(rule.inline.port)) {
			let ports = [];
			for (let p in rule.inline.port) push(ports, int(p));
			push(route_rules, { port: ports, outbound: target });
		}
	}

	if (!group_tags.default) push(errors, '默认出口组不存在：没有可用节点');
	if (length(errors)) return { ok: false, errors: errors, warnings: warnings };

	/* direct 是空出站，1.14.4 拒绝把它作为 DNS detour；direct-dns 带 tcp_fast_open 因此非空。 */
	let dns_servers = [{ type: 'udp', tag: 'dns-direct', server: '223.5.5.5', detour: 'direct-dns' }];
	if (dns_mode != 'system')
		push(dns_servers, {
			type: 'https', tag: 'dns-proxy', server: '1.1.1.1', detour: 'default',
			/* 服务器地址是 IP，用固定 SNI 校验证书，避免依赖 1.1.1.1 的 IP SAN。 */
			tls: { enabled: true, server_name: 'cloudflare-dns.com' }
		});
	if (ts.enabled && dns_mode != 'system')
		push(dns_servers, { type: 'tailscale', tag: TAILSCALE_DNS_TAG, endpoint: TAILSCALE_TAG, accept_default_resolvers: true });
	if (dns_mode == 'proxy') {
		/* proxy mode means all DNS through the proxy, but MagicDNS names only
		   exist inside the tailnet: keep the preferred_by rule, drop the rest. */
		let kept = [];
		for (let r in dns_rules) if (r.preferred_by) push(kept, r);
		dns_rules = kept;
	}
	if (ts.enabled && dns_mode == 'system')
		push(warnings, 'DNS 模式为 system，Tailscale MagicDNS 不会生效');
	let dns = {
		servers: dns_servers,
		rules: dns_mode == 'system' ? [] : dns_rules,
		final: dns_mode == 'system' ? 'dns-direct' : 'dns-proxy',
		strategy: (cfg.dns && cfg.dns.strategy) || 'prefer_ipv4',
		cache_capacity: 8192
	};

	/* TUN is the only inbound: auto_redirect requires auto_route and Linux nftables. */
	let tun_address = [];
	for (let a in as_list((cfg.inbound && cfg.inbound.address) || '172.19.0.1/30,fdfe:dcba:9876::1/126'))
		if (length(trim(a))) push(tun_address, trim(a));
	if (!length(tun_address))
		tun_address = [ '172.19.0.1/30', 'fdfe:dcba:9876::1/126' ];
	let tun_mtu = int((cfg.inbound && cfg.inbound.mtu) || 9000);
	if (tun_mtu < 1280 || tun_mtu > 65535) {
		push(warnings, sprintf('TUN MTU %d 无效，已回退到 9000', tun_mtu));
		tun_mtu = 9000;
	}
	let inbound = {
		type: 'tun',
		tag: 'tun-in',
		address: tun_address,
		mtu: tun_mtu,
		auto_route: true,
		auto_redirect: true,
		strict_route: (cfg.inbound && cfg.inbound.strict_route == '1'),
		dns_mode: 'hijack'
	};
	if (cfg.inbound && cfg.inbound.exclude_cn != '0' && length(route_exclude_tags))
		inbound.route_exclude_address_set = route_exclude_tags;

	let experimental = {
		cache_file: { enabled: true, path: PATH.etc + '/cache.db', store_dns: true }
	};
	let services = null;
	let panel = cfg.panel || {};
	if (panel.enabled == '1') {
		let listen = trim(panel.listen || '127.0.0.1');
		if (!length(listen)) listen = '127.0.0.1';
		let port = int(panel.port || 9090);
		if (port < 1 || port > 65535) port = 9090;
		let secret = trim(panel.secret || '');
		let dashboard = (panel.dashboard || 'native') == 'official' ? 'official' : 'native';
		if (!length(secret)) push(warnings, '面板已启用但 API 密钥为空，API 将不校验密钥');
		if (dashboard == 'official') {
			/*
			 * The official sing-box dashboard is a client of the sing-box API
			 * service (gRPC-Web), not the Clash API. It is served by the API
			 * listener at /dashboard/; using clash_api.external_ui here would
			 * serve files the dashboard cannot talk to.
			 */
			let api = { type: 'api', tag: 'api', listen: listen, listen_port: port };
			if (length(secret)) api.secret = secret;
			let ui = PATH.etc + '/ui';
			if (file_exists(ui + '/index.html'))
				api.dashboard = { enabled: true, path: ui };
			else
				push(warnings, '已选择官方面板，但面板文件尚未下载（设置 → 面板 → 下载面板文件）');
			if (listen == '127.0.0.1' || listen == '::1' || listen == '[::1]')
				push(warnings, '官方面板需要 sing-box API 监听 0.0.0.0 或局域网地址，当前仅监听本机');
			services = [ api ];
		} else {
			experimental.clash_api = {
				external_controller: listen_address(listen, port),
				secret: secret
			};
		}
	}

	let config = {
		log: { level: (cfg.main && cfg.main.log_level) || 'info', timestamp: true },
		dns: dns,
		inbounds: [ inbound ],
		outbounds: outbounds,
		route: {
			rules: route_rules,
			rule_set: rule_set_defs,
			final: ts.use_default ? TAILSCALE_TAG : 'default',
			default_domain_resolver: 'dns-direct',
			auto_detect_interface: true
		},
		experimental: experimental
	};
	if (ts.enabled) config.endpoints = [ ts.endpoint ];
	if (services) config.services = services;
	return { ok: true, config: config, warnings: warnings, errors: [] };
}

function config_json(cfg, collected) {
	let result = build_config(cfg, collected);
	if (!result.ok) return result;
	return { ok: true, json: sprintf('%J', result.config), warnings: result.warnings };
}

export { build_config, config_json };
