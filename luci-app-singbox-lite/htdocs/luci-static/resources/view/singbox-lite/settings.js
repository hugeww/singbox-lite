'use strict';

'require view';
'require form';
'require uci';
'require ui';
'require tools.singbox-lite as api';

function notify(title, msg, type) {
	ui.addNotification(title, msg, type || 'info');
}

function mergeTags(list, current) {
	let out = [];
	for (let i = 0; i < (list || []).length; i++) {
		let tag = list[i];
		if (tag && out.indexOf(tag) < 0) out.push(tag);
	}
	if (current && out.indexOf(current) < 0) out.push(current);
	return out;
}

function confirmAction(title, message, action) {
	return new Promise(function(resolve) {
		ui.showModal(title, [
			E('p', {}, message),
			E('div', { class: 'right' }, [
				E('button', {
					class: 'btn',
					click: function() { ui.hideModal(); }
				}, _('Cancel')),
				' ',
				E('button', {
					class: 'btn cbi-button-positive important',
					click: function() {
						ui.hideModal();
						resolve(action());
					}
				}, _('Continue'))
			])
		]);
	});
}

function pollPluginUpdate() {
	return new Promise(function(resolve) {
		let tries = 0;
		let timer = setInterval(function() {
			api.pluginUpdateStatus().then(function(st) {
				let state = st && st.state;
				if (state == 'done' || state == 'error') {
					clearInterval(timer);
					resolve(st);
				} else if (++tries > 150) {
					clearInterval(timer);
					resolve(null);
				}
			}).catch(function() {
				clearInterval(timer);
				resolve(null);
			});
		}, 2000);
	});
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('singbox-lite'),
			api.status().catch(function() { return null; }),
			api.releaseList().catch(function() { return null; })
		]);
	},

	render: function(data) {
		let status = (data && data[1]) || {};
		let cached = (data && data[2]) || {};
		let coreInfo = status.core || {};
		let pluginInfo = status.plugin || {};
		let coreTags = mergeTags(cached.core, uci.get('singbox-lite', 'version_core', 'core_tag'));
		let pluginTags = mergeTags(cached.plugin, uci.get('singbox-lite', 'version', 'plugin_tag'));

		let m = new form.Map('singbox-lite', _('Settings'),
			_('Service, inbound, DNS, automatic refresh and core settings.'));

		let top = api.actionTable(m, _('Actions'));
		let saveBtn = top.option(form.Button, '_save_check', _('Save & Check Config'));
		saveBtn.inputstyle = 'positive';
		saveBtn.onclick = function() {
			return m.save().then(function() { return api.configSave(); }).then(function(r) {
				ui.addNotification(_('Config'), r.ok ? _('Saved. Restart the service to apply.') : ((r.errors || []).join('\n') || r.detail || r.error || _('Check failed')), r.ok ? 'info' : 'danger');
			});
		};

		let checkBtn = top.option(form.Button, '_check_updates', _('Check for updates'));
		checkBtn.onclick = function() {
			return m.save().then(function() { return api.releaseScan(); }).then(function(r) {
				if (r && r.ok) {
					notify(_('Versions'), _('Version list refreshed.'), 'info');
					window.location.reload();
				} else {
					notify(_('Versions'), (r && r.error) || _('Check failed'), 'danger');
				}
			});
		};

		let s = m.section(form.NamedSection, 'version', 'version', _('Plugin'));
		s.anonymous = false;

		let o = s.option(form.DummyValue, '_plugin_arch', _('Architecture'));
		o.cfgvalue = function() {
			return pluginInfo.arch || '-';
		};

		o = s.option(form.DummyValue, '_plugin_version', _('Plugin version'));
		o.cfgvalue = function() {
			let v = pluginInfo.version || '-';
			return pluginInfo.installed === false ? v + ' (' + _('not installed') + ')' : v;
		};

		o = s.option(form.DummyValue, '_plugin_latest', _('Latest available'));
		o.cfgvalue = function() {
			return (cached.plugin && cached.plugin.length) ? cached.plugin[0] : '-';
		};

		o = s.option(form.ListValue, 'plugin_tag', _('Select version'));
		o.value('', _('Latest'));
		for (let i = 0; i < pluginTags.length; i++)
			o.value(pluginTags[i], pluginTags[i]);
		o.default = '';

		o = s.option(form.Button, '_plugin_update', _('Update plugin'));
		o.inputstyle = 'positive';
		o.onclick = function() {
			return m.save().then(function() {
				let tag = uci.get('singbox-lite', 'version', 'plugin_tag') || '';
				return confirmAction(_('Update plugin'),
					_('The selected release will be downloaded and installed with apk, replacing singbox-lite and luci-app-singbox-lite.'),
					function() {
						return api.pluginUpdate(tag || null).then(function(r) {
							if (!r || !r.ok) {
								notify(_('Plugin update'), (r && r.error) || _('Update failed'), 'danger');
								return;
							}
							notify(_('Plugin update'), _('Update started. Waiting for completion...'), 'info');
							return pollPluginUpdate().then(function(st) {
								if (!st) return;
								if (st.state == 'done') {
									notify(_('Plugin update'), _('Plugin updated to ') + (st.version || st.tag || '') + '. ' + _('Reload the page to use the new UI.'), 'info');
									setTimeout(function() { window.location.reload(); }, 1500);
								} else {
									notify(_('Plugin update'), (st.detail || st.error || _('Update failed')), 'danger');
								}
							});
						});
					});
			});
		};

		s = m.section(form.NamedSection, 'version_core', 'version_core', _('Core'));
		s.anonymous = false;

		o = s.option(form.DummyValue, '_core_version', _('Core version'));
		o.cfgvalue = function() {
			let v = coreInfo.version || _('not installed');
			if (coreInfo.meets_minimum === false) v += ' (' + _('below 1.14.4') + ')';
			return v;
		};

		o = s.option(form.DummyValue, '_core_latest', _('Latest available'));
		o.cfgvalue = function() {
			return (cached.core && cached.core.length) ? cached.core[0] : '-';
		};

		o = s.option(form.ListValue, 'core_tag', _('Select version'));
		o.value('', _('Latest'));
		for (let i = 0; i < coreTags.length; i++)
			o.value(coreTags[i], coreTags[i]);
		o.default = '';

		o = s.option(form.Button, '_core_update', _('Update core'));
		o.inputstyle = 'positive';
		o.onclick = function() {
			return m.save().then(function() {
				let tag = uci.get('singbox-lite', 'version_core', 'core_tag') || '';
				return confirmAction(_('Update core'),
					_('The selected sing-box version will be downloaded, verified and the service restarted.'),
					function() {
						return api.coreUpdate(tag || null).then(function(r) {
							notify(_('Core update'), r && r.ok ? _('Update started; refresh later for status') : ((r && r.error) || _('Update failed')), r && r.ok ? 'info' : 'danger');
						});
					});
			});
		};

		o = s.option(form.Button, '_core_rollback', _('Rollback Core'));
		o.inputstyle = 'negative';
		o.onclick = function() {
			return api.coreRollback().then(function(r) {
				notify(_('Core rollback'), r.ok ? _('Rolled back to ') + (r.version || '') : (r.error || _('Rollback failed')), r.ok ? 'info' : 'danger');
			});
		};

		s = m.section(form.NamedSection, 'main', 'main', _('Main'));
		s.anonymous = false;

		o = s.option(form.Flag, 'enabled', _('Autostart on boot'));
		o.rmempty = false;

		o = s.option(form.ListValue, 'core_source', _('Core source'));
		o.value('managed', _('Managed download'));
		o.value('system', _('System /usr/bin/sing-box (>= 1.14.4)'));
		o.default = 'managed';

		o = s.option(form.Value, 'core_mirror', _('Core download mirror'));
		o.placeholder = 'https://ghfast.top/';

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

		s = m.section(form.NamedSection, 'panel', 'panel', _('Panel'),
			_('Clash API used by the live panel page. Restart the service after changing it.'));
		s.anonymous = false;

		o = s.option(form.Flag, 'enabled', _('Enable panel'));
		o.rmempty = false;
		o.default = '1';

		o = s.option(form.ListValue, 'dashboard', _('Panel type'));
		o.value('official', _('Official sing-box dashboard'));
		o.value('native', _('Built-in LuCI panel'));
		o.default = 'official';

		o = s.option(form.Value, 'listen', _('Listen address'));
		o.placeholder = '127.0.0.1';

		o = s.option(form.Value, 'port', _('Listen port'));
		o.datatype = 'port';
		o.default = '9090';

		o = s.option(form.Value, 'secret', _('API secret'));

		o = s.option(form.Button, '_gen_secret', _('Generate secret'));
		o.onclick = function() {
			return api.panelSecret().then(function(r) {
				if (r && r.ok) {
					notify(_('Panel'), _('New secret generated. Save and restart the service to apply it.'), 'info');
					window.location.reload();
				} else {
					notify(_('Panel'), (r && r.error) || _('Action failed'), 'danger');
				}
			});
		};

		o = s.option(form.Button, '_dashboard_update', _('Download dashboard files'));
		o.inputstyle = 'action';
		o.onclick = function() {
			return api.dashboardUpdate().then(function(r) {
				if (!r || !r.ok) {
					notify(_('Panel'), (r && r.error) || _('Action failed'), 'danger');
					return;
				}
				notify(_('Panel'), _('Downloading dashboard files...'), 'info');
				let tries = 0;
				let timer = setInterval(function() {
					api.dashboardUpdateStatus().then(function(st) {
						let state = st && st.state;
						if (state == 'done') {
							clearInterval(timer);
							notify(_('Panel'), _('Dashboard files updated. Save and restart the service to apply.'), 'info');
						} else if (state == 'error') {
							clearInterval(timer);
							notify(_('Panel'), (st.error || _('Action failed')), 'danger');
						} else if (++tries > 150) {
							clearInterval(timer);
						}
					}).catch(function() { clearInterval(timer); });
				}, 2000);
			});
		};

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