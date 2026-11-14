'use strict';

'require view';
'require form';
'require uci';
'require ui';
'require tools.singbox-lite as api';

function addTargets(option) {
	option.value('direct', _('Direct'));
	option.value('default', _('Default group'));
	option.value('auto', _('Auto group'));
	option.value('us', _('US group'));
	option.value('jp', _('Japan group'));
	option.value('hk', _('Hong Kong group'));
	option.value('other', _('Other countries'));
	option.value('native', _('Native group'));
	let groups = uci.sections('singbox-lite', 'egress_group') || [];
	for (let g of groups)
		if (g.enabled != '0')
			option.value(g['.name'], g.name || g['.name']);
}

return view.extend({
	load: function() {
		return uci.load('singbox-lite');
	},

	render: function() {
		let m = new form.Map('singbox-lite', _('Rule Sets & Routing'),
			_('Built-in rule sets are read-only; custom rule sets are evaluated before built-in ones. Select the egress group each rule set should use.'));

		let top = m.section(form.TableSection, 'placeholder_ruleset_actions', _('Rule-set data'));
		top.anonymous = true;
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
			addTargets(opt);
			opt.default = rs.target || 'direct';
			s.option(form.Flag, 'enabled', _('Enabled')).default = '1';
			s.option(form.DummyValue, '_kind', _('Type')).cfgvalue = function() { return _('Built-in (read-only content)'); };
		}

		let saveTop = m.section(form.TableSection, 'placeholder_save', _('Actions'));
		saveTop.anonymous = true;
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
		addTargets(o);

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
