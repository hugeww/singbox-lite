'use strict';

'require view';
'require form';
'require uci';
'require ui';
'require tools.singbox-lite as api';

function splitMembers(value) {
	if (value == null)
		return [];
	if (Array.isArray(value))
		return value.filter(function(v) { return v != null && v !== ''; });
	return String(value).split(',').map(function(v) { return v.trim(); }).filter(function(v) { return v !== ''; });
}

/* api.status() payload when the backend replied, null when it is unavailable. */
function groupStatus(status) {
	if (!status || status.ok !== true || !status.groups || !Array.isArray(status.node_list))
		return null;
	return status;
}

/* Custom groups the generator will actually create: members must resolve to a known node. */
function customGroups(status) {
	let groups = (uci.sections('singbox-lite', 'egress_group') || []).filter(function(g) { return g.enabled != '0'; });
	if (status == null)
		return groups;
	let nodes = {};
	for (let n of status.node_list) {
		if (!n)
			continue;
		for (let id of [ n.id, n.legacy_id, n.fingerprint ])
			if (id)
				nodes[id] = n;
	}
	return groups.filter(function(g) {
		for (let id of splitMembers(g.members)) {
			let node = nodes[id];
			if (!node)
				continue;
			/* URLTest groups skip native nodes, mirroring the generator. */
			if ((g.type || 'selector') == 'urltest' && node.native)
				continue;
			return true;
		}
		return false;
	});
}

function addTargets(option, status, groups, current) {
	let seen = {};
	function add(key, label) {
		seen[key] = true;
		option.value(key, label);
	}
	add('direct', _('Direct'));
	add('default', _('Default group'));
	let counts = status ? status.groups : null;
	function has(name) {
		return counts ? (parseInt(counts[name] || 0, 10) > 0) : true;
	}
	if (has('auto'))
		add('auto', _('Auto group'));
	if (has('us'))
		add('us', _('US group'));
	if (has('jp'))
		add('jp', _('Japan group'));
	if (has('hk'))
		add('hk', _('Hong Kong group'));
	if (has('other'))
		add('other', _('Other countries'));
	if (has('native'))
		add('native', _('Native group'));
	for (let g of groups)
		add(g['.name'], g.name || g['.name']);
	/*
	 * Keep a saved target visible even when the group is currently
	 * unavailable (no members / status unknown); otherwise the list widget
	 * would silently fall back and a later save could rewrite the rule.
	 */
	if (current && !seen[current])
		option.value(current, current + ' (' + _('unavailable') + ')');
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('singbox-lite'),
			api.status().catch(function() { return {}; })
		]);
	},

	render: function(data) {
		let status = groupStatus(data ? data[1] : null);
		let groups = customGroups(status);
		let description = _('Built-in rule sets are read-only; custom rule sets are evaluated before built-in ones. Select the egress group each rule set should use.');
		if (status == null)
			description += ' ' + _('Node status is unavailable, so egress groups that have no members may still be listed.');
		let m = new form.Map('singbox-lite', _('Rule Sets & Routing'), description);

		let top = api.actionTable(m, _('Rule-set data'));
		let o = top.option(form.Button, '_update_builtin', _('Update Built-in Rule Sets'));
		o.onclick = function() {
			return api.rulesetUpdate(null).then(function(r) {
				ui.addNotification(_('Rule sets'), r.ok ? _('Updated') : ((r.failed || []).join(', ') || r.error || _('Update failed')), r.ok ? 'info' : 'danger');
			});
		};
		o = top.option(form.Button, '_install_yq', _('Install yq'));
		o.onclick = function() {
			return api.installYq().then(function(r) {
				ui.addNotification(_('yq'), r.ok ? _('Installed') : (r.error || _('Install failed')), r.ok ? 'info' : 'danger');
			});
		};

		o = top.option(form.Button, '_yq', _('Check yq'));
		o.onclick = function() {
			return api.yqStatus().then(function(r) {
				ui.addNotification(_('yq'), r.installed ? _('Installed') : _('Not installed; Clash YAML subscriptions need yq'), r.installed ? 'info' : 'warning');
			});
		};

		let builtins = (uci.sections('singbox-lite', 'ruleset') || []).filter(function(s) { return s.kind == 'builtin'; });
		for (let rs of builtins) {
			let s = m.section(form.NamedSection, rs['.name'], 'ruleset', rs.name || rs['.name']);
			s.anonymous = false;
			let opt = s.option(form.ListValue, 'target', _('Egress group'));
			addTargets(opt, status, groups, rs.target);
			opt.default = rs.target || 'direct';
			s.option(form.Flag, 'enabled', _('Enabled')).default = '1';
			s.option(form.DummyValue, '_kind', _('Type')).cfgvalue = function() { return _('Built-in (read-only content)'); };
		}

		let saveTop = api.actionTable(m, _('Actions'));
		let sb = saveTop.option(form.Button, '_save_check', _('Save & Check Config'));
		sb.inputstyle = 'positive';
		sb.onclick = function() {
			return m.save().then(function() { return api.configSave(); }).then(function(r) {
				ui.addNotification(_('Config'), r.ok ? _('Saved. Restart the service to apply.') : ((r.errors || []).join('\n') || r.detail || r.error || _('Check failed')), r.ok ? 'info' : 'danger');
			});
		};

		let grid = m.section(form.GridSection, 'ruleset', _('Custom Rule Sets'));
		grid.addremove = true;
		grid.anonymous = false;
		grid.filter = function(section_id) { return uci.get('singbox-lite', section_id, 'kind') != 'builtin'; };

		o = grid.option(form.Value, 'name', _('Name'));
		o.rmempty = false;

		o = grid.option(form.ListValue, 'type', _('Source'));
		o.value('inline', _('Inline domain/IP list'));
		o.value('remote', _('Remote .srs URL'));
		o.value('local', _('Local .srs path'));
		o.default = 'inline';

		o = grid.option(form.TextValue, 'domains', _('Inline domains/IPs'));
		o.placeholder = 'example.com\n1.2.3.0/24\nport:8080';
		o.rows = 4;

		o = grid.option(form.Value, 'url', _('Remote URL'));
		o.placeholder = 'https://example.com/rules.srs';

		o = grid.option(form.Value, 'path', _('Local path'));
		o.placeholder = '/etc/singbox-lite/rulesets/custom.srs';

		o = grid.option(form.ListValue, 'target', _('Egress group'));
		addTargets(o, status, groups, null);

		o = grid.option(form.Flag, 'enabled', _('Enabled'));
		o.default = '1';

		o = grid.option(form.Value, 'order', _('Order'));
		o.datatype = 'uinteger';
		o.placeholder = '10';

		o = grid.option(form.Button, '_update', _('Update'));
		o.onclick = function(section_id) {
			return api.rulesetUpdate(section_id).then(function(r) {
				ui.addNotification(_('Rule set'), r.ok ? _('Updated') : (r.error || _('Update failed')), r.ok ? 'info' : 'danger');
			});
		};

		return m.render();
	}
});
