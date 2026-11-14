'use strict';

'require view';
'require form';
'require uci';
'require ui';
'require tools.singbox-lite as api';

function notify(title, msg, type) {
	ui.addNotification(title, msg, type || 'info');
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('singbox-lite'),
			api.status(),
			api.coreStatus()
		]);
	},

	render: function(data) {
		let status = data[1] || {};
		let core = data[2] || {};
		let coreInfo = core.core || status.core || {};
		let m = new form.Map('singbox-lite', _('sing-box Lite'),
			_('Bare-core sing-box manager: subscriptions, rule sets, egress groups and core updates.'));

		let s = m.section(form.TableSection, 'placeholder', _('Status'));
		s.anonymous = true;

		let o = s.option(form.DummyValue, '_running', _('Service'));
		o.cfgvalue = function() {
			return status.running ? _('Running') + (status.pid ? ' (PID ' + status.pid + ')' : '') : _('Stopped');
		};

		o = s.option(form.DummyValue, '_core', _('Core'));
		o.cfgvalue = function() {
			return (coreInfo.version || _('not installed')) + (coreInfo.meets_minimum === false ? ' (' + _('below 1.14.4') + ')' : '');
		};

		o = s.option(form.DummyValue, '_nodes', _('Nodes'));
		o.cfgvalue = function() {
			return String(status.nodes || 0);
		};

		o = s.option(form.DummyValue, '_pending', _('Config state'));
		o.cfgvalue = function() {
			return status.pending ? _('Saved; restart required') : _('In sync');
		};

		o = s.option(form.Button, '_start', _('Start'));
		o.inputstyle = 'positive';
		o.onclick = function() {
			return api.serviceControl('start').then(function(r) {
				notify(_('Service'), r.ok ? _('Started') : (r.error || _('Start failed')), r.ok ? 'info' : 'danger');
			});
		};

		o = s.option(form.Button, '_stop', _('Stop'));
		o.inputstyle = 'negative';
		o.onclick = function() {
			return api.serviceControl('stop').then(function(r) {
				notify(_('Service'), r.ok ? _('Stopped') : (r.error || _('Stop failed')), r.ok ? 'info' : 'danger');
			});
		};

		o = s.option(form.Button, '_restart', _('Restart'));
		o.inputstyle = 'action';
		o.onclick = function() {
			return api.serviceControl('restart').then(function(r) {
				notify(_('Service'), r.ok ? _('Restarted') : (r.error || _('Restart failed')), r.ok ? 'info' : 'danger');
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
				if (r.ok)
					notify(_('Config'), _('Configuration saved. Restart the service to apply it.'), 'info');
				else
					notify(_('Config check failed'), (r.errors || []).join('\n') || r.detail || r.error || '', 'danger');
			});
		};

		s = m.section(form.TableSection, 'placeholder_core', _('Core'));
		s.anonymous = true;

		o = s.option(form.DummyValue, '_core_version', _('Version'));
		o.cfgvalue = function() { return coreInfo.version || '-'; };

		o = s.option(form.DummyValue, '_core_path', _('Path'));
		o.cfgvalue = function() { return coreInfo.path || '-'; };

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
				notify(_('Core update'), r.ok ? _('Update started; refresh later for status') : (r.error || _('Update failed')), r.ok ? 'info' : 'danger');
			});
		};

		o = s.option(form.Button, '_core_rollback', _('Rollback Core'));
		o.inputstyle = 'negative';
		o.onclick = function() {
			return api.coreRollback().then(function(r) {
				notify(_('Core rollback'), r.ok ? _('Rolled back to ') + (r.version || '') : (r.error || _('Rollback failed')), r.ok ? 'info' : 'danger');
			});
		};

		if (status.warnings && status.warnings.length) {
			s = m.section(form.TableSection, 'placeholder_warnings', _('Warnings'));
			s.anonymous = true;
			o = s.option(form.DummyValue, '_warnings', _('Warnings'));
			o.cfgvalue = function() { return status.warnings.join('\n'); };
		}

		return m.render();
	}
});
