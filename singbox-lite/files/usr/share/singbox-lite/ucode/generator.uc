'use strict';

import { trim, split_csv, PATH } from 'sbx_common';
import { group_nodes, find_node } from 'sbx_nodes';
import { resolve_rulesets, rule_set_tag } from 'sbx_rulesets';

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
			if (n.id == id) return n.tag;
	}
	return length(members) ? members[0].tag : null;
}

function custom_group_tag(name) {
	let t = tag_slug(name);
	if (substr(t, 0, 3) != 'eg_') t = 'eg_' + t;
	return t;
}

function build_config(cfg, collected) {
	let warnings = [];
	let errors = [];
	let nodes = collected.nodes;
	let groups = group_nodes(nodes);

	if (!length(nodes)) push(errors, '没有可用节点：请先添加订阅或手动节点');

	let egress = cfg.egress || {};
	let outbounds = [{ type: 'direct', tag: 'direct' }];
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

	/* custom egress groups */
	let custom_groups = {};
	for (let g in cfg.egress_groups || []) {
		if (g.enabled == '0') continue;
		let tag = custom_group_tag(g['.name']);
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
	let route_rules = [
		{ action: 'sniff' },
		{ ip_is_private: true, outbound: 'direct' }
	];
	let dns_rules = [];
	let used_file_tags = {};

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
				used_file_tags[f.tag] = true;
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

	let dns_mode = cfg.dns && cfg.dns.mode ? cfg.dns.mode : 'split';
	let dns_servers = [{ type: 'local', tag: 'dns-direct' }];
	if (dns_mode != 'system')
		push(dns_servers, { type: 'https', tag: 'dns-proxy', server: '1.1.1.1', detour: 'default' });
	if (dns_mode == 'proxy')
		dns_rules = [];
	let dns = {
		servers: dns_servers,
		rules: dns_mode == 'system' ? [] : dns_rules,
		final: dns_mode == 'system' ? 'dns-direct' : 'dns-proxy',
		strategy: (cfg.dns && cfg.dns.strategy) || 'prefer_ipv4'
	};

	let inbound = {
		type: 'mixed',
		tag: 'mixed-in',
		listen: (cfg.inbound && cfg.inbound.listen) || '0.0.0.0',
		listen_port: int((cfg.inbound && cfg.inbound.port) || 7890)
	};
	if (cfg.inbound && cfg.inbound.auth == '1') {
		if (!length(cfg.inbound.username || '') || !length(cfg.inbound.password || '')) {
			push(warnings, '已启用入站认证但用户名/密码为空，使用默认 admin/admin');
			inbound.users = [{ username: 'admin', password: 'admin' }];
		} else {
			inbound.users = [{ username: cfg.inbound.username, password: cfg.inbound.password }];
		}
	}

	let experimental = {
		cache_file: { enabled: true, path: PATH.etc + '/cache.db' }
	};
	let panel = cfg.panel || {};
	if (panel.enabled == '1') {
		let listen = trim(panel.listen || '127.0.0.1');
		if (!length(listen)) listen = '127.0.0.1';
		let port = int(panel.port || 9090);
		if (port < 1 || port > 65535) port = 9090;
		let secret = trim(panel.secret || '');
		if (!length(secret)) push(warnings, '面板已启用但 API 密钥为空，Clash API 将不校验密钥');
		experimental.clash_api = {
			external_controller: listen + ':' + port,
			secret: secret
		};
	}

	let config = {
		log: { level: (cfg.main && cfg.main.log_level) || 'info', timestamp: true },
		dns: dns,
		inbounds: [ inbound ],
		outbounds: outbounds,
		route: {
			rules: route_rules,
			rule_set: rule_set_defs,
			final: 'default',
			default_domain_resolver: 'dns-direct',
			auto_detect_interface: true
		},
		experimental: experimental
	};
	return { ok: true, config: config, warnings: warnings, errors: [] };
}

function config_json(cfg, collected) {
	let result = build_config(cfg, collected);
	if (!result.ok) return result;
	return { ok: true, json: sprintf('%J', result.config), warnings: result.warnings };
}

export { build_config, config_json };
