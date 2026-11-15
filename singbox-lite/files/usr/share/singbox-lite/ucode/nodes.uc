'use strict';

import { trim, split_csv, read_json, stable_id, PATH } from 'sbx_common';
import { parse_manual_input } from 'sbx_links';

const DEFAULT_COUNTRY = {
	us: '美国,US,USA,United States,洛杉矶,圣何塞,西雅图,纽约,芝加哥,达拉斯,硅谷,🇺🇸',
	jp: '日本,JP,Japan,东京,大阪,埼玉,🇯🇵',
	hk: '香港,HK,Hong Kong,🇭🇰'
};

const DEFAULT_NATIVE = '原生,原生IP,native,家宽,住宅,residential';

/*
 * 机场常把「剩余流量」「到期时间」「去官网更新」这类信息条目伪装成节点塞进订阅，
 * 它们连不上，只会在面板/分组里占位。命中这些关键词的条目直接跳过。
 */
const DEFAULT_INFO_KEYWORDS = '剩余流量,流量剩余,到期时间,过期时间,下次重置,重置时间,套餐,官网,客服,公告';

function regexp_escape(s) {
	let out = '';
	for (let i = 0; i < length(s); i++) {
		let c = substr(s, i, 1);
		if (index('.^$*+?()[]{}|\\', c) >= 0)
			out += '\\';
		out += c;
	}
	return out;
}

function has_keyword(name, keyword) {
	name = lc(name == null ? '' : name);
	keyword = lc(keyword == null ? '' : keyword);
	if (!length(keyword)) return false;
	if (match(keyword, /^[a-z0-9._-]+$/)) {
		/*
		 * 机场常把数字直接粘在国别码后面（US01/JP01/HK01/native01），所以
		 * 边界只排除 ASCII 字母：数字、连字符、空格、中文都算分隔符。
		 * Russia/AUS 里的 "us" 前面是字母，仍然不会被误匹配。
		 */
		let re = regexp('(^|[^a-z])' + regexp_escape(keyword) + '([^a-z]|$)');
		return match(name, re) != null;
	}
	return index(name, keyword) >= 0;
}

/*
 * 规范化 outbound 供指纹使用：递归按键名排序（保证同一节点无论来自 URI、
 * Clash 还是 sing-box JSON 订阅都得到同一 JSON），去掉 null，数组顺序保留
 * （例如 alpn 的顺序有语义）。
 */
function canonical_identity(value) {
	if (type(value) == 'object') {
		let out = {};
		for (let k in sort(keys(value))) {
			if (value[k] == null) continue;
			out[k] = canonical_identity(value[k]);
		}
		return out;
	}
	if (type(value) == 'array') {
		let out = [];
		for (let item in value) {
			if (item == null) continue;
			push(out, canonical_identity(item));
		}
		return out;
	}
	return value;
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

/*
 * Compatibility id: the pre-2026-11-15 fingerprint. It is not used for new
 * node ids, but UCI written by older versions (node_overrides.id, egress group
 * members/default_node) still references it. Keep it as a lookup alias so an
 * upgrade does not silently lose user overrides or group membership.
 */
function legacy_fingerprint(outbound) {
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

/*
 * 节点身份必须覆盖整个 outbound：同服务器/同端口/同 UUID、但 ws path、
 * SNI、flow、obfs、plugin 不同的节点是不同节点，不能因为指纹过粗被
 * collect_nodes() 当成重复节点丢掉。整份 outbound（去掉展示用的 tag/name）
 * 规范化后取哈希，既不会把不同节点合并，又能让完全相同的节点去重。
 */
function node_fingerprint(outbound) {
	if (!outbound || type(outbound) != 'object') return stable_id([ '' ]);
	let identity = {};
	for (let k in keys(outbound)) {
		if (k == 'tag' || k == 'name') continue;
		if (outbound[k] == null) continue;
		identity[k] = outbound[k];
	}
	/* 不同来源可能把数字写成字符串，先归一化，避免同一节点被拆成两个。 */
	if (identity.server_port != null) identity.server_port = int(identity.server_port);
	if (identity.alter_id != null) identity.alter_id = int(identity.alter_id);
	return stable_id([ sprintf('%J', canonical_identity(identity)) ]);
}

/*
 * Node ids are always lowercase (stable_id hashes lowercase input), but UCI
 * section names keep the case the user typed, so an override section written
 * as "ov_AB12CD" would never match id "ab12cd".
 */
function override_key(id) {
	return lc(trim(id == null ? '' : id));
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
		map[override_key(ov.id)] = ov;
	}
	return map;
}

/*
 * 节点对外显示名（sing-box tag / Clash API 里的 proxy name）。
 * 保留订阅里的可读名称，后缀 [id] 保证唯一：不同节点同名时不会撞 tag，
 * 也不会因为订阅刷新顺序变化而让引用失效（引用一律通过 n.tag / n.id 获取）。
 */
function node_tag(name, id) {
	let label = trim(name || '');
	if (length(label) > 48)
		label = substr(label, 0, 48);
	return (length(label) ? label : 'node') + ' [' + id + ']';
}

function is_info_node(name, cfg) {
	let keywords = split_csv((cfg && cfg.main && cfg.main.info_keywords) || DEFAULT_INFO_KEYWORDS);
	for (let kw in keywords)
		if (has_keyword(name, kw))
			return true;
	return false;
}

function collect_nodes(cfg) {
	let candidates = [];
	let warnings = [];
	let seen = {};
	let overrides = override_map(cfg);

	/*
	 * Two passes: collect unique outbounds by full fingerprint first, then
	 * assign ids. A node whose legacy id is unique keeps that legacy id, so
	 * UCI written by older versions (overrides, egress-group members,
	 * default_node) keeps working after the fingerprint change. Only nodes
	 * that would collide on the legacy id get the new full-fingerprint id.
	 */
	function add_candidate(raw, source, source_name) {
		if (!raw || !raw.outbound) return;
		let outbound = raw.outbound;
		let fingerprint = node_fingerprint(outbound);
		if (seen[fingerprint]) {
			push(warnings, sprintf('重复节点已跳过：%s（来源 %s）', raw.name || outbound.server, source_name));
			return;
		}
		let legacy_id = legacy_fingerprint(outbound);
		let ov = overrides[override_key(fingerprint)] || overrides[override_key(legacy_id)] || {};
		if (ov.enabled == '0') return;
		let name = trim(raw.name || outbound.server || 'node');
		if (is_info_node(name, cfg)) {
			push(warnings, sprintf('已跳过信息节点：%s', name));
			return;
		}
		seen[fingerprint] = true;
		push(candidates, {
			raw: raw, source: source, source_name: source_name,
			outbound: outbound, fingerprint: fingerprint, legacy_id: legacy_id,
			override: ov, name: name
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
			add_candidate(n, 'subscription:' + sub['.name'], sub.name || sub['.name']);
	}

	for (let n in cfg.nodes) {
		if (n.enabled == '0') continue;
		let parsed = parse_manual_input(n.link || '');
		if (!parsed.ok) {
			push(warnings, sprintf('手动节点 %s 解析失败：%s', n.name || n['.name'], parsed.error));
			continue;
		}
		add_candidate(parsed, 'manual:' + n['.name'], n.name || '手动节点');
	}

	let legacy_count = {};
	for (let c in candidates)
		legacy_count[c.legacy_id] = (legacy_count[c.legacy_id] || 0) + 1;
	let used_ids = {};
	let nodes = [];
	for (let c in candidates) {
		let id = legacy_count[c.legacy_id] == 1 ? c.legacy_id : c.fingerprint;
		/* Extremely unlikely 32-bit hash collision: keep ids unique. */
		if (used_ids[id]) id = c.fingerprint;
		let base = id;
		let n = 2;
		while (used_ids[id]) id = base + '_' + (n++);
		used_ids[id] = true;
		let ov = c.override;
		let country = ov.country && ov.country != 'auto' ? ov.country : classify_country(c.name, cfg.egress);
		let native = ov.native_mode == '1' ? true : (ov.native_mode == '0' ? false : (ov.native == '1' ? true : (ov.native == '0' ? false : is_native(c.name, cfg.egress))));
		let native_mode = length(ov.native_mode || '') ? ov.native_mode : (ov.native || 'auto');
		push(nodes, {
			id: id,
			legacy_id: c.legacy_id,
			fingerprint: c.fingerprint,
			tag: node_tag(c.name, id),
			name: c.name,
			type: c.raw.type || c.outbound.type,
			server: c.raw.server || c.outbound.server,
			server_port: int(c.raw.server_port || c.outbound.server_port || 0),
			outbound: c.outbound,
			source: c.source,
			source_name: c.source_name,
			country: country,
			country_mode: ov.country || 'auto',
			native: native,
			native_mode: native_mode
		});
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
		if (n.id == id || n.legacy_id == id || n.fingerprint == id) return n;
	return null;
}

export { classify_country, is_native, node_fingerprint, legacy_fingerprint, node_tag, override_key, collect_nodes, group_nodes, find_node };
