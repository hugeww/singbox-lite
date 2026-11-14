'use strict';

'require view';
'require form';
'require uci';
'require tools.singbox-lite as api';

function findOverride(id) {
	let sections = uci.sections('singbox-lite', 'node_override') || [];
	for (let i = 0; i < sections.length; i++)
		if (sections[i].id == id)
			return sections[i];
	return null;
}

function setOverride(id, field, value) {
	let section = findOverride(id);
	let sid;
	if (section) {
		sid = section['.name'];
	} else {
		sid = uci.add('singbox-lite', 'node_override', 'ov_' + id);
		if (!sid) return Promise.resolve();
		uci.set('singbox-lite', sid, 'id', id);
	}
	// The backend reads the explicit native IP mode from the `native_mode`
	// option; `native` is only consulted as a fallback for older configs.
	uci.set('singbox-lite', sid, field == 'native' ? 'native_mode' : field, value);
	return uci.save().then(function() { return uci.apply(); });
}

function countrySelect(node) {
	let values = [ [ 'auto', _('Auto') ], [ 'us', _('US') ], [ 'jp', _('Japan') ], [ 'hk', _('Hong Kong') ], [ 'other', _('Other') ] ];
	let opts = [];
	for (let i = 0; i < values.length; i++)
		opts.push(E('option', { value: values[i][0], selected: node.country == values[i][0] ? true : null }, values[i][1]));
	return E('select', {
		class: 'cbi-input-select',
		change: function(ev) { setOverride(node.id, 'country', ev.target.value); }
	}, opts);
}

function nativeSelect(node) {
	let current = node.native_mode || (node.native ? '1' : '0');
	let opts = [
		E('option', { value: 'auto', selected: current == 'auto' ? true : null }, _('Auto')),
		E('option', { value: '1', selected: current == '1' ? true : null }, _('Yes')),
		E('option', { value: '0', selected: current == '0' ? true : null }, _('No'))
	];
	return E('select', {
		class: 'cbi-input-select',
		change: function(ev) { setOverride(node.id, 'native', ev.target.value); }
	}, opts);
}

return view.extend({
	load: function() {
		return Promise.all([ uci.load('singbox-lite'), api.status() ]);
	},

	render: function(data) {
		let status = data[1] || {};
		let nodes = status.node_list || [];
		let rows = [
			E('tr', { class: 'tr table-titles' }, [
				E('th', { class: 'th' }, _('Name')),
				E('th', { class: 'th' }, _('ID')),
				E('th', { class: 'th' }, _('Source')),
				E('th', { class: 'th' }, _('Type')),
				E('th', { class: 'th' }, _('Server')),
				E('th', { class: 'th' }, _('Country')),
				E('th', { class: 'th' }, _('Native IP'))
			])
		];
		for (let n of nodes) {
			rows.push(E('tr', { class: 'tr' }, [
				E('td', { class: 'td' }, n.name || '-'),
				E('td', { class: 'td' }, E('code', {}, n.id || '-')),
				E('td', { class: 'td' }, n.source || '-'),
				E('td', { class: 'td' }, n.type || '-'),
				E('td', { class: 'td' }, (n.server || '') + ':' + (n.port || '')),
				E('td', { class: 'td' }, countrySelect(n)),
				E('td', { class: 'td' }, nativeSelect(n))
			]));
		}
		let table = E('div', { class: 'cbi-section' }, [
			E('h3', {}, _('Detected Nodes')),
			E('p', { class: 'cbi-section-descr' }, _('Country and native-IP overrides are saved by node ID and survive subscription refresh.')),
			nodes.length ? E('table', { class: 'table' }, rows) : E('p', {}, _('No nodes yet. Update a subscription or add a manual node.'))
		]);

		let m = new form.Map('singbox-lite', _('Manual Nodes'), _('Paste share links or complete sing-box outbound JSON.'));
		let s = m.section(form.GridSection, 'node', _('Manual Nodes'));
		s.addremove = true;
		s.anonymous = false;
		let o = s.option(form.Value, 'name', _('Name'));
		o.rmempty = false;
		o = s.option(form.Value, 'link', _('Share Link / JSON'));
		o.rmempty = false;
		o.placeholder = 'vless://... or {"type":"vless", ...}';
		o = s.option(form.Flag, 'enabled', _('Enabled'));
		o.default = '1';
		o.rmempty = false;

		return m.render().then(function(formNode) {
			return E('div', {}, [ table, formNode ]);
		});
	}
});
