'use strict';

'require view';
'require form';
'require uci';
'require ui';
'require tools.singbox-lite as api';

function addNodes(option, nodes, allowEmpty) {
	if (allowEmpty)
		option.value('', _('Auto / first member'));
	for (let n of nodes) {
		let label = (n.name || n.id) + ' [' + (n.country || 'other') + ']';
		option.value(n.id, label);
		/* Collision nodes get a new id; keep the old one selectable so UCI
		   written before the fingerprint change still shows its selection. */
		if (n.legacy_id && n.legacy_id != n.id)
			option.value(n.legacy_id, label + ' (' + _('legacy id') + ')');
	}
}

return view.extend({
	load: function() {
		return Promise.all([ uci.load('singbox-lite'), api.status() ]);
	},

	render: function(data) {
		let status = data[1] || {};
		let nodes = status.node_list || [];
		let m = new form.Map('singbox-lite', _('Egress Groups'),
			_('Built-in groups are based on node country; the native group is manual and never auto-selected. Custom groups select nodes explicitly.'));

		let s = m.section(form.NamedSection, 'egress', 'egress', _('Built-in Egress Groups'));
		s.anonymous = false;

		let o = s.option(form.ListValue, 'default_group', _('Default group target'));
		o.value('auto', _('Auto group'));
		o.value('us', _('US group'));
		o.value('jp', _('Japan group'));
		o.value('hk', _('Hong Kong group'));
		o.value('other', _('Other countries'));
		o.default = 'auto';

		o = s.option(form.Value, 'auto_url', _('Auto test URL'));
		o.placeholder = 'https://www.gstatic.com/generate_204';
		o = s.option(form.Value, 'auto_interval', _('Auto test interval'));
		o.placeholder = '10m';
		o = s.option(form.Value, 'auto_tolerance', _('Auto test tolerance (ms)'));
		o.datatype = 'uinteger';

		let defaults = [
			[ 'us_default', _('US default node') ],
			[ 'jp_default', _('Japan default node') ],
			[ 'hk_default', _('Hong Kong default node') ],
			[ 'other_default', _('Other countries default node') ],
			[ 'native_default', _('Native default node') ]
		];
		for (let d of defaults) {
			o = s.option(form.ListValue, d[0], d[1]);
			addNodes(o, nodes, true);
			o.optional = true;
		}

		o = s.option(form.Value, 'us_keywords', _('US name keywords'));
		o = s.option(form.Value, 'jp_keywords', _('Japan name keywords'));
		o = s.option(form.Value, 'hk_keywords', _('Hong Kong name keywords'));
		o = s.option(form.Value, 'native_keywords', _('Native IP name keywords'));
		o.placeholder = '原生,原生IP,native,家宽,住宅,residential';

		let saveTop = api.actionTable(m, _('Actions'));
		let sb = saveTop.option(form.Button, '_save_check', _('Save & Check Config'));
		sb.inputstyle = 'positive';
		sb.onclick = function() {
			return m.save().then(function() { return api.configSave(); }).then(function(r) {
				ui.addNotification(_('Config'), r.ok ? _('Saved. Restart the service to apply.') : ((r.errors || []).join('\n') || r.detail || r.error || _('Check failed')), r.ok ? 'info' : 'danger');
			});
		};

		let grid = m.section(form.GridSection, 'egress_group', _('Custom Egress Groups'));
		grid.addremove = true;
		grid.anonymous = false;

		o = grid.option(form.Value, 'name', _('Name'));
		o.rmempty = false;

		o = grid.option(form.ListValue, 'type', _('Type'));
		o.value('selector', _('Selector (manual)'));
		o.value('urltest', _('URLTest (auto)'));
		o.default = 'selector';

		o = grid.option(form.ListValue, 'members', _('Member nodes'));
		o.multiple = true;
		addNodes(o, nodes, false);
		o.description = _('Native nodes are excluded from URLTest groups.');

		o = grid.option(form.ListValue, 'default_node', _('Default node'));
		addNodes(o, nodes, true);
		o.optional = true;

		o = grid.option(form.Value, 'interval', _('Test interval'));
		o.placeholder = '10m';
		o = grid.option(form.Value, 'tolerance', _('Tolerance (ms)'));
		o.datatype = 'uinteger';

		o = grid.option(form.Flag, 'enabled', _('Enabled'));
		o.default = '1';

		return m.render();
	}
});
