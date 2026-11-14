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
		let m = new form.Map('singbox-lite', _('Settings'),
			_('Service, inbound, DNS, automatic refresh and core settings.'));

		let top = m.section(form.TableSection, 'placeholder_save', _('Actions'));
		top.anonymous = true;
		let saveBtn = top.option(form.Button, '_save_check', _('Save & Check Config'));
		saveBtn.inputstyle = 'positive';
		saveBtn.onclick = function() {
			return m.save().then(function() { return api.configSave(); }).then(function(r) {
				ui.addNotification(_('Config'), r.ok ? _('Saved. Restart the service to apply.') : ((r.errors || []).join('\n') || r.detail || r.error || _('Check failed')), r.ok ? 'info' : 'danger');
			});
		};

		let s = m.section(form.NamedSection, 'main', 'main', _('Main'));
		s.anonymous = false;

		let o = s.option(form.Flag, 'enabled', _('Autostart on boot'));
		o.rmempty = false;

		o = s.option(form.ListValue, 'core_source', _('Core source'));
		o.value('managed', _('Managed download'));
		o.value('system', _('System /usr/bin/sing-box (>= 1.14.4)'));
		o.default = 'managed';

		o = s.option(form.Value, 'core_mirror', _('Core download mirror'));
		o.placeholder = 'https://ghfast.top/';

		o = s.option(form.Value, 'core_version', _('Core version pin'));
		o.placeholder = 'empty = latest stable';

		o = s.option(form.Flag, 'auto_update', _('Scheduled subscription refresh'));
		o.default = '1';
		o = s.option(form.Value, 'update_interval', _('Refresh interval (hours)'));
		o.datatype = 'uinteger';
		o.default = '6';
		o = s.option(form.Flag, 'auto_apply', _('Restart after scheduled refresh'));
		o.default = '1';

		o = s.option(form.ListValue, 'log_level', _('Log level'));
		o.value('debug', 'debug');
		o.value('info', 'info');
		o.value('warn', 'warn');
		o.value('error', 'error');
		o.default = 'info';

		o = s.option(form.Value, 'log_max_kb', _('Log max size (KB)'));
		o.datatype = 'uinteger';
		o.default = '2048';

		s = m.section(form.NamedSection, 'inbound', 'inbound', _('Inbound'));
		s.anonymous = false;
		o = s.option(form.Value, 'listen', _('Listen address'));
		o.placeholder = '0.0.0.0';
		o = s.option(form.Value, 'port', _('Listen port'));
		o.datatype = 'port';
		o.default = '7890';
		o = s.option(form.Flag, 'auth', _('Enable username/password'));
		o = s.option(form.Value, 'username', _('Username'));
		o.optional = true;
		o = s.option(form.Value, 'password', _('Password'));
		o.password = true;
		o.optional = true;

		s = m.section(form.NamedSection, 'dns', 'dns', _('DNS'));
		s.anonymous = false;
		o = s.option(form.ListValue, 'mode', _('DNS mode'));
		o.value('split', _('Split: CN direct, rest proxy'));
		o.value('system', _('System DNS only'));
		o.value('proxy', _('All DNS through proxy'));
		o.default = 'split';
		o = s.option(form.ListValue, 'strategy', _('Strategy'));
		o.value('prefer_ipv4', 'prefer_ipv4');
		o.value('prefer_ipv6', 'prefer_ipv6');
		o.value('ipv4_only', 'ipv4_only');
		o.value('ipv6_only', 'ipv6_only');
		o.default = 'prefer_ipv4';

		return m.render();
	}
});
