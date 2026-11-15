'use strict';

'require view';
'require form';
'require uci';
'require ui';
'require tools.singbox-lite as api';

function notify(title, msg, type) {
	ui.addNotification(title, msg, type || 'info');
}

function checkError(r) {
	return (r && (r.errors || []).length ? r.errors.join('\n') : ((r && (r.detail || r.error)) || _('Check failed')));
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('singbox-lite'),
			api.status().catch(function() { return null; })
		]);
	},

	render: function(data) {
		let status = (data && data[1]) || {};
		let ts = status.tailscale || {};

		let m = new form.Map('singbox-lite', _('Tailscale'),
			_('Join this router to a tailnet: reach home devices without port forwarding, route remote subnets, or use a tailnet exit node.') +
			' ' + _('The generated config adds endpoints[type=tailscale], a MagicDNS DNS server and preferred_by rules.') +
			' ' + _('Requires a sing-box 1.14.4+ binary built with with_tailscale/with_gvisor (official releases are).'));

		let s = api.actionTable(m, _('Actions'));

		let o = s.option(form.Button, '_save_check', _('Save & Check Config'));
		o.inputstyle = 'positive';
		o.onclick = function() {
			return m.save().then(function() { return api.configSave(); }).then(function(r) {
				if (r && r.ok)
					notify(_('Tailscale'), _('Configuration saved. Restart the service to apply it.'), 'info');
				else
					notify(_('Tailscale'), checkError(r), 'danger');
			});
		};

		o = s.option(form.Button, '_save_apply', _('Save & Restart'));
		o.inputstyle = 'action';
		o.onclick = function() {
			return m.save().then(function() { return api.configSave(); }).then(function(r) {
				if (!r || !r.ok) {
					notify(_('Tailscale'), checkError(r), 'danger');
					return;
				}
				return api.serviceControl('restart').then(function(svc) {
					notify(_('Tailscale'), svc && svc.ok ? _('Restarted') : ((svc && svc.error) || _('Restart failed')),
						svc && svc.ok ? 'info' : 'danger');
					if (svc && svc.ok)
						window.setTimeout(function() { window.location.reload(); }, 1500);
				});
			});
		};

		s.option(form.DummyValue, '_ts_state', _('State')).cfgvalue = function() {
			if (!ts.enabled) return _('Disabled');
			if (!ts.in_config) return _('Enabled; save the configuration');
			if (!ts.in_active) return _('Saved; restart the service');
			return _('Active');
		};

		s.option(form.DummyValue, '_ts_login', _('Login URL')).cfgvalue = function() {
			if (ts.auth_url) return ts.auth_url;
			if (!ts.enabled) return '-';
			return _('No login URL yet. Restart the service, then check Logs for "Waiting for authentication".');
		};

		o = s.option(form.Button, '_ts_open_login', _('Open login page'));
		o.onclick = function() {
			if (!ts.auth_url) {
				notify(_('Tailscale'), _('No login URL yet. Restart the service and check the log.'), 'warning');
				return;
			}
			window.open(ts.auth_url, '_blank', 'noopener');
		};

		s = m.section(form.NamedSection, 'tailscale', 'tailscale', _('Tailscale'));
		s.anonymous = false;
		s.addremove = false;

		o = s.option(form.Flag, 'enabled', _('Enable Tailscale'));
		o.default = '0';
		o.rmempty = false;
		o.description = _('When enabled, the router becomes a tailnet node. Traffic to tailnet peers, MagicDNS names and accepted subnet routes is routed into the endpoint before the private-IP direct rule.');

		o = s.option(form.TextValue, 'auth_key', _('Auth key'),
			_('Recommended for unattended routers (tskey-auth-...). Leave empty to log in interactively through the URL printed in the core log.'));
		o.password = true;
		o.placeholder = 'tskey-auth-...';
		o.rmempty = true;

		o = s.option(form.TextValue, 'hostname', _('Hostname'),
			_('Name shown in the Tailscale admin console. Defaults to the system hostname.'));
		o.placeholder = _('System hostname');
		o.rmempty = true;

		o = s.option(form.TextValue, 'state_directory', _('State directory'),
			_('Node identity and keys are stored here; it must survive reboots. Relative paths resolve under /etc/singbox-lite.'));
		o.default = '/etc/singbox-lite/tailscale';
		o.rmempty = false;

		o = s.option(form.Flag, 'accept_routes', _('Accept subnet routes'),
			_('Use subnets advertised by other tailnet nodes. Their ranges are matched by the preferred_by route rule.'));
		o.default = '0';

		o = s.option(form.TextValue, 'advertise_routes', _('Advertise routes'),
			_('Comma-separated CIDRs advertised to the tailnet so peers can reach your LAN, e.g. 192.168.1.0/24. Approve them in the Tailscale admin console. The default route is not allowed here.'));
		o.placeholder = '192.168.1.0/24';
		o.rmempty = true;

		o = s.option(form.Flag, 'advertise_exit_node', _('Advertise as exit node'),
			_('Let other tailnet devices send all their traffic through this router. Approve the exit node in the Tailscale admin console.'));
		o.default = '0';

		o = s.option(form.TextValue, 'exit_node', _('Use exit node'),
			_('Name or IP of a tailnet exit node. Only traffic routed to the endpoint uses it; enable the option below to make it the default egress.'));
		o.placeholder = 'vps-exit';
		o.rmempty = true;

		o = s.option(form.Flag, 'exit_node_allow_lan_access', _('Allow LAN access through exit node'),
			_('Keep local LAN destinations reachable directly while the exit node is in use.'));
		o.default = '0';

		o = s.option(form.Flag, 'exit_node_default', _('Default egress via exit node'),
			_('Make the tailnet exit node the route final: traffic not matched by any rule set leaves through it instead of the default proxy group. Requires an exit node above.'));
		o.default = '0';

		return m.render();
	}
});