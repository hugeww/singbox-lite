'use strict';

import { readfile } from 'fs';
import { read_json } from 'sbx_common';

const UCI_NAME = 'singbox-lite';

function load_env_config() {
	let path = getenv('SINGBOX_LITE_CONFIG_JSON');
	if (!length(path || '')) return null;
	return read_json(path, null);
}

function load_uci_config() {
	let uci;
	try { uci = require('uci'); } catch (e) { uci = null; }
	if (!uci) die('ucode uci module unavailable');
	let ctx = uci.cursor();
	ctx.load(UCI_NAME);
	let all = ctx.get_all(UCI_NAME) || {};
	let cfg = {
		main: {}, inbound: {}, dns: {}, egress: {},
		rulesets: [], egress_groups: [], subscriptions: [], nodes: [], node_overrides: []
	};
	for (let name in keys(all)) {
		let s = all[name];
		let t = s['.type'];
		s['.name'] = name;
		if (t == 'main') cfg.main = s;
		else if (t == 'inbound') cfg.inbound = s;
		else if (t == 'dns') cfg.dns = s;
		else if (t == 'egress') cfg.egress = s;
		else if (t == 'ruleset') push(cfg.rulesets, s);
		else if (t == 'egress_group') push(cfg.egress_groups, s);
		else if (t == 'subscription') push(cfg.subscriptions, s);
		else if (t == 'node') push(cfg.nodes, s);
		else if (t == 'node_override') push(cfg.node_overrides, s);
	}
	return cfg;
}

function load_config() {
	let cfg = load_env_config() || load_uci_config();
	for (let key in [ 'rulesets', 'egress_groups', 'subscriptions', 'nodes', 'node_overrides' ])
		if (!cfg[key]) cfg[key] = [];
	sort(cfg.rulesets, (a, b) => int(a.order || 1000) - int(b.order || 1000));
	sort(cfg.egress_groups, (a, b) => (a['.name'] < b['.name']) ? -1 : ((a['.name'] > b['.name']) ? 1 : 0));
	return cfg;
}

function uci_set(section, option, value) {
	return system(['uci', '-q', 'set', UCI_NAME + '.' + section + '.' + option + '=' + value]);
}

function uci_set_section(section, type) {
	return system(['uci', '-q', 'set', UCI_NAME + '.' + section + '=' + type]);
}

function uci_delete(section, option) {
	if (option)
		return system(['uci', '-q', 'delete', UCI_NAME + '.' + section + '.' + option]);
	return system(['uci', '-q', 'delete', UCI_NAME + '.' + section]);
}

function uci_commit() {
	return system(['uci', '-q', 'commit', UCI_NAME]);
}

export { UCI_NAME, load_config, uci_set, uci_set_section, uci_delete, uci_commit };
