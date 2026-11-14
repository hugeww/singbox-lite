'use strict';

import { trim, split_csv, read_json, stable_id, PATH } from 'sbx_common';
import { parse_manual_input } from 'sbx_links';

const DEFAULT_COUNTRY = {
	us: '美国,US,USA,United States,洛杉矶,圣何塞,西雅图,纽约,芝加哥,达拉斯,硅谷,🇺🇸',
	jp: '日本,JP,Japan,东京,大阪,埼玉,🇯🇵',
	hk: '香港,HK,Hong Kong,🇭🇰'
};

const DEFAULT_NATIVE = '原生,原生IP,native,家宽,住宅,residential';

function has_keyword(name, keyword) {
	name = lc(name == null ? '' : name);
	keyword = lc(keyword == null ? '' : keyword);
	if (!length(keyword)) return false;
	if (match(keyword, /^[a-z0-9._-]+$/)) {
		let re = regexp('(^|[^a-z0-9])' + replace(keyword, /([.\\-])/g, '\\$1') + '([^a-z0-9]|$)');
		return match(name, re) != null;
	}
	return index(name, keyword) >= 0;
}

function classify_country(name, egress) {
	let keys = {
		us: split_csv((egress && egress.us_keywords) || DEFAULT_COUNTRY.us),
		jp: split_csv((egress && egress.jp_keywords) || DEFAULT_COUNTRY.jp),
		hk: split_csv((egress && egress.hk_keywords) || DEFAULT_COUNTRY.hk)
	};
	for (let country in [ 'us', 'jp', 'hk' ]) {
		for (let kw in keys[country])
			if (has_keyword(name, kw))
				return country;
	}
	return 'other';
}

function is_native(name, egress) {
	let keywords = split_csv((egress && egress.native_keywords) || DEFAULT_NATIVE);
	for (let kw in keywords)
		if (has_keyword(name, kw))
			return true;
	return false;
}

function node_fingerprint(outbound) {
	let secret = '';
	if (outbound.uuid) secret = outbound.uuid;
	else if (outbound.password) secret = outbound.password;
	if (outbound.method) secret = outbound.method + ':' + (outbound.password || '');
	if (outbound.username) secret = outbound.username + ':' + (outbound.password || '');
	return stable_id([
		outbound.type || '',
		outbound.server || '',
		sprintf('%d', int(outbound.server_port || 0)),
		secret
	]);
}

function as_list(v) {
	if (v == null) return [];
	if (type(v) == 'array') return v;
	return split_csv(v);
}

function override_map(cfg) {
	let map = {};
	for (let ov in cfg.node_overrides || []) {
		if (!ov.id) continue;
		map[ov.id] = ov;
	}
	return map;
}

function collect_nodes(cfg) {
	let nodes = [];
	let warnings = [];
	let seen = {};
	let overrides = override_map(cfg);

	function add_node(raw, source, source_name) {
		if (!raw || !raw.outbound) return;
		let outbound = raw.outbound;
		let id = node_fingerprint(outbound);
		if (seen[id]) {
			push(warnings, sprintf('重复节点已跳过：%s（来源 %s）', raw.name || outbound.server, source_name));
			return;
		}
		let ov = overrides[id] || {};
		if (ov.enabled == '0') return;
		let name = trim(raw.name || outbound.server || 'node');
		let country = ov.country && ov.country != 'auto' ? ov.country : classify_country(name, cfg.egress);
		let native = ov.native == '1' ? true : (ov.native == '0' ? false : is_native(name, cfg.egress));
		let native_mode = ov.native || 'auto';
		seen[id] = true;
		push(nodes, {
			id: id,
			tag: 'node_' + id,
			name: name,
			type: raw.type || outbound.type,
			server: raw.server || outbound.server,
			server_port: int(raw.server_port || outbound.server_port || 0),
			outbound: outbound,
			source: source,
			source_name: source_name,
			country: country,
			country_mode: ov.country || 'auto',
			native: native,
			native_mode: native_mode
		});
	}

	for (let sub in cfg.subscriptions) {
		if (sub.enabled == '0') continue;
		let meta = read_json(PATH.meta_dir + '/' + sub['.name'] + '.json', null);
		if (!meta || type(meta.nodes) != 'array') {
			push(warnings, sprintf('订阅 %s 尚无解析结果，请先更新', sub.name || sub['.name']));
			continue;
		}
		for (let n in meta.nodes)
			add_node(n, 'subscription:' + sub['.name'], sub.name || sub['.name']);
	}

	for (let n in cfg.nodes) {
		if (n.enabled == '0') continue;
		let parsed = parse_manual_input(n.link || '');
		if (!parsed.ok) {
			push(warnings, sprintf('手动节点 %s 解析失败：%s', n.name || n['.name'], parsed.error));
			continue;
		}
		add_node(parsed, 'manual:' + n['.name'], n.name || '手动节点');
	}

	return { nodes: nodes, warnings: warnings };
}

function group_nodes(nodes) {
	let groups = { us: [], jp: [], hk: [], other: [], native: [], auto: [] };
	for (let n in nodes) {
		if (n.native) {
			/* Native nodes are manual-only: keep them out of country, other, auto and default groups. */
			push(groups.native, n);
			continue;
		}
		if (n.country == 'us' || n.country == 'jp' || n.country == 'hk')
			push(groups[n.country], n);
		else
			push(groups.other, n);
		push(groups.auto, n);
	}
	return groups;
}

function find_node(nodes, id) {
	for (let n in nodes)
		if (n.id == id) return n;
	return null;
}

export { classify_country, is_native, node_fingerprint, collect_nodes, group_nodes, find_node };
