'use strict';

'require view';
'require form';
'require uci';
'require ui';
'require tools.singbox-lite as api';

return view.extend({
	load: function() {
		return uci.load('singbox-lite');
	},

	render: function() {
		let m = new form.Map('singbox-lite', _('Subscriptions'),
			_('Add airport or self-hosted subscriptions. Base64/URI lists, sing-box JSON and Clash YAML (with yq) are supported.'));

		let top = m.section(form.TableSection, 'placeholder_actions', _('Actions'));
		top.anonymous = true;
		let o = top.option(form.Button, '_update_all', _('Update All'));
		o.inputstyle = 'positive';
		o.onclick = function() {
			return api.subscriptionUpdateAll().then(function(r) {
				ui.addNotification(_('Subscriptions'), r.ok ? _('Update started. Check status later.') : (r.error || _('Update failed')), r.ok ? 'info' : 'danger');
			});
		};

		let s = m.section(form.GridSection, 'subscription', _('Subscriptions'));
		s.addremove = true;
		s.anonymous = false;

		o = s.option(form.Value, 'name', _('Name'));
		o.rmempty = false;

		o = s.option(form.Value, 'url', _('Subscription URL'));
		o.rmempty = false;
		o.placeholder = 'https://example.com/sub?token=...';

		o = s.option(form.ListValue, 'format', _('Format'));
		o.value('auto', _('Auto detect'));
		o.value('uri', _('URI list / base64'));
		o.value('clash', _('Clash YAML (yq)'));
		o.value('singbox', _('sing-box JSON'));
		o.default = 'auto';

		o = s.option(form.Value, 'ua', _('User-Agent'));
		o.placeholder = 'sing-box/1.14';
		o.optional = true;

		o = s.option(form.Flag, 'enabled', _('Enabled'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.DummyValue, 'status', _('Status'));
		o.cfgvalue = function(section_id) {
			return uci.get('singbox-lite', section_id, 'status') || 'never';
		};

		o = s.option(form.DummyValue, 'last_update', _('Last update'));
		o.cfgvalue = function(section_id) {
			return (uci.get('singbox-lite', section_id, 'last_update') || '-');
		};

		o = s.option(form.DummyValue, 'traffic', _('Traffic'));
		o.cfgvalue = function(section_id) {
			let used = uci.get('singbox-lite', section_id, 'used') || '-';
			let total = uci.get('singbox-lite', section_id, 'total') || '-';
			let expire = uci.get('singbox-lite', section_id, 'expire') || '';
			return used + ' / ' + total + (expire ? ' (' + expire + ')' : '');
		};

		o = s.option(form.Button, '_update', _('Update'));
		o.onclick = function(section_id) {
			return api.subscriptionUpdate(section_id).then(function(r) {
				ui.addNotification(_('Subscription'), r.ok ? _('Updated') : (r.error || _('Update failed')), r.ok ? 'info' : 'danger');
			});
		};

		return m.render();
	}
});
