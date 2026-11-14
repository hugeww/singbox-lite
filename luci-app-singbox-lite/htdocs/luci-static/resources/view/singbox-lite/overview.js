'use strict';

'require view';
'require form';
'require uci';
'require ui';
'require tools.singbox-lite as api';

const CORE_POLL_INTERVAL = 1500;
const CORE_POLL_TIMEOUT = 6 * 60 * 1000;

function notify(title, msg, type) {
	ui.addNotification(title, msg, type || 'info');
}

function sleep(ms) {
	return new Promise(function(res) { window.setTimeout(res, ms); });
}

function pollUntil(fetch, done, interval, deadline) {
	return fetch().then(function(r) {
		r = r || {};
		if (done(r) || Date.now() > deadline)
			return r;
		return sleep(interval).then(function() { return pollUntil(fetch, done, interval, deadline); });
	});
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('singbox-lite'),
			api.status(),
			api.coreStatus(),
			api.coreUpdateStatus()
		]);
	},

	render: function(data) {
		let status = data[1] || {};
		let core = data[2] || {};
		let coreUpdate = data[3] || {};
		let coreInfo = core.core || status.core || {};

		/*
		 * DummyValue cells are rendered once, so live values are written into the
		 * rendered table by their data-name attribute instead of re-rendering the
		 * whole map (which would discard whatever the user is editing).
		 */
		let live = {
			running: status.running,
			pid: status.pid,
			nodes: status.nodes || 0,
			pending: status.pending,
			version: coreInfo.version,
			belowMinimum: coreInfo.meets_minimum === false,
			update: coreUpdate.state || 'idle'
		};
		let root = null;

		function describeCoreUpdate(s) {
			switch (s.state) {
			case 'checking': return _('Querying the latest version…');
			case 'downloading': return _('Downloading %s').format(s.url || '');
			case 'installing': return _('Installing %s').format(s.message || s.version || '');
			case 'restarting': return _('Restarting with %s…').format(s.version || '');
			case 'rolling-back': return _('New core failed to start, rolling back…');
			case 'done': return _('Core updated to %s').format(s.version || '');
			case 'error': return _('Update failed: %s').format(s.error || '');
			default: return '-';
			}
		}

		function paint(name, text) {
			if (!root || text == null)
				return;
			let cell = root.querySelector('[data-name="%s"]'.format(name));
			if (cell)
				cell.textContent = text;
		}

		function syncCells() {
			paint('_running', live.running
				? _('Running') + (live.pid ? ' (PID ' + live.pid + ')' : '')
				: _('Stopped'));
			paint('_core', (live.version || _('not installed'))
				+ (live.belowMinimum ? ' (' + _('below 1.14.4') + ')' : ''));
			paint('_nodes', String(live.nodes || 0));
			paint('_pending', live.pending ? _('Saved; restart required') : _('In sync'));
			paint('_core_version', live.version || '-');
			paint('_core_update_state', describeCoreUpdate({
				state: live.update, url: coreUpdate.url,
				version: coreUpdate.version, error: coreUpdate.error
			}));
		}

		function refreshStatus() {
			return api.status().then(function(r) {
				r = r || {};
				let c = (r.core && r.core.version) ? r.core : null;
				live.running = r.running;
				live.pid = r.pid;
				live.nodes = r.nodes || 0;
				live.pending = r.pending;
				if (c) {
					live.version = c.version;
					live.belowMinimum = c.meets_minimum === false;
				}
				syncCells();
				return r;
			});
		}

		function refreshUpdateStatus() {
			return api.coreUpdateStatus().then(function(r) {
				r = r || {};
				coreUpdate = r;
				live.update = r.state || 'idle';
				syncCells();
				return r;
			});
		}

		let o;
		let m = new form.Map('singbox-lite', _('sing-box Lite'),
			_('TUN sing-box manager: subscriptions, rule sets, egress groups and core updates.'));

		let s = api.actionTable(m, _('Status'));

		let refreshBtn = s.option(form.Button, '_refresh', _('Refresh'));
		refreshBtn.onclick = function() {
			return Promise.all([ refreshStatus(), refreshUpdateStatus() ]).then(function() {
				notify(_('Status'), _('Refreshed'), 'info');
			});
		};

		s.option(form.DummyValue, '_running', _('Service'))
			.cfgvalue = function() {
				return live.running ? _('Running') + (live.pid ? ' (PID ' + live.pid + ')' : '') : _('Stopped');
			};

		s.option(form.DummyValue, '_core', _('Core'))
			.cfgvalue = function() {
				return (live.version || _('not installed'))
					+ (live.belowMinimum ? ' (' + _('below 1.14.4') + ')' : '');
			};

		s.option(form.DummyValue, '_nodes', _('Nodes'))
			.cfgvalue = function() { return String(live.nodes || 0); };

		s.option(form.DummyValue, '_pending', _('Config state'))
			.cfgvalue = function() { return live.pending ? _('Saved; restart required') : _('In sync'); };

		o = s.option(form.Button, '_start', _('Start'));
		o.inputstyle = 'positive';
		o.onclick = function() {
			return api.serviceControl('start').then(function(r) {
				notify(_('Service'), r.ok ? _('Started') : (r.error || _('Start failed')), r.ok ? 'info' : 'danger');
				return refreshStatus();
			});
		};

		o = s.option(form.Button, '_stop', _('Stop'));
		o.inputstyle = 'negative';
		o.onclick = function() {
			return api.serviceControl('stop').then(function(r) {
				notify(_('Service'), r.ok ? _('Stopped') : (r.error || _('Stop failed')), r.ok ? 'info' : 'danger');
				return refreshStatus();
			});
		};

		o = s.option(form.Button, '_restart', _('Restart'));
		o.inputstyle = 'action';
		o.onclick = function() {
			return api.serviceControl('restart').then(function(r) {
				notify(_('Service'), r.ok ? _('Restarted') : (r.error || _('Restart failed')), r.ok ? 'info' : 'danger');
				return refreshStatus();
			});
		};

		o = s.option(form.Button, '_preview', _('Preview Config'));
		o.onclick = function() {
			return api.configPreview().then(function(r) {
				let text = r.ok ? JSON.stringify(r.config, null, 2) : ((r.errors || []).join('\n') || r.error || '');
				ui.showModal(_('Config Preview'), [
					E('pre', { style: 'max-height:60vh;overflow:auto;white-space:pre-wrap;font-size:12px;' }, text),
					E('button', { class: 'btn cbi-button', click: function() { ui.hideModal(); } }, _('Close'))
				]);
			});
		};

		o = s.option(form.Button, '_save_apply', _('Save & Check Config'));
		o.onclick = function() {
			return api.configSave().then(function(r) {
				if (r.ok) {
					notify(_('Config'), _('Configuration saved. Restart the service to apply it.'), 'info');
					return refreshStatus();
				}
				notify(_('Config check failed'), (r.errors || []).join('\n') || r.detail || r.error || '', 'danger');
			});
		};

		s = api.actionTable(m, _('Core'));

		o = s.option(form.DummyValue, '_plugin_version', _('Plugin version'));
		o.cfgvalue = function() { return (status.plugin && status.plugin.version) || '-'; };

		s.option(form.DummyValue, '_core_version', _('Version'))
			.cfgvalue = function() { return live.version || '-'; };

		s.option(form.DummyValue, '_core_path', _('Path'))
			.cfgvalue = function() { return coreInfo.path || '-'; };

		s.option(form.DummyValue, '_core_update_state', _('Update state'))
			.cfgvalue = function() {
				return describeCoreUpdate({
					state: live.update, url: coreUpdate.url,
					version: coreUpdate.version, error: coreUpdate.error
				});
			};

		o = s.option(form.Button, '_core_check', _('Check Latest'));
		o.onclick = function() {
			return api.coreCheckLatest().then(function(r) {
				notify(_('Core update'), r.ok ? (r.tag + ' / ' + r.asset) : (r.error || _('Check failed')), r.ok ? 'info' : 'danger');
			});
		};

		o = s.option(form.Button, '_core_update', _('Update Core'));
		o.inputstyle = 'positive';
		o.onclick = function() {
			return api.coreUpdate().then(function(r) {
				if (!r.ok) {
					notify(_('Core update'), r.error || _('Update failed'), 'danger');
					return;
				}
				notify(_('Core update'), _('Update started, progress is shown below.'), 'info');
				let deadline = Date.now() + CORE_POLL_TIMEOUT;
				return pollUntil(refreshUpdateStatus, function(s) {
					return s.state == 'done' || s.state == 'error';
				}, CORE_POLL_INTERVAL, deadline).then(function(s) {
					if (s.state == 'done')
						notify(_('Core update'), _('Core updated to %s').format(s.version || ''), 'info');
					else if (s.state == 'error')
						notify(_('Core update'), _('Update failed: %s').format(s.error || ''), 'danger');
					else
						notify(_('Core update'), _('Still running, check back later.'), 'warning');
					return refreshStatus();
				});
			});
		};

		o = s.option(form.Button, '_core_rollback', _('Rollback Core'));
		o.inputstyle = 'negative';
		o.onclick = function() {
			return api.coreRollback().then(function(r) {
				notify(_('Core rollback'), r.ok ? _('Rolled back to ') + (r.version || '') : (r.error || _('Rollback failed')), r.ok ? 'info' : 'danger');
				return refreshStatus();
			});
		};

		if (status.warnings && status.warnings.length) {
			s = api.actionTable(m, _('Warnings'));
			o = s.option(form.DummyValue, '_warnings', _('Warnings'));
			o.cfgvalue = function() { return status.warnings.join('\n'); };
		}

		return m.render().then(function(node) {
			root = node;
			syncCells();

			/* an update started earlier (page reload, another browser) keeps reporting progress */
			if (live.update != 'idle' && live.update != 'done' && live.update != 'error') {
				let deadline = Date.now() + CORE_POLL_TIMEOUT;
				pollUntil(refreshUpdateStatus, function(s) {
					return s.state == 'done' || s.state == 'error';
				}, CORE_POLL_INTERVAL, deadline).then(refreshStatus);
			}

			return node;
		});
	}
});