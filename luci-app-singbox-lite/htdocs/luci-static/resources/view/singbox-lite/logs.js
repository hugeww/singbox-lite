'use strict';

'require view';
'require ui';
'require tools.singbox-lite as api';

return view.extend({
	load: function() {
		return api.logTail(200);
	},

	render: function(data) {
		let text = (data && data.text) || '';
		let pre = E('pre', {
			id: 'singbox_lite_log',
			style: 'max-height:60vh; overflow:auto; white-space:pre-wrap; font-size:12px;'
		}, text || _('No log output.'));

		return E('div', { class: 'cbi-section' }, [
			E('h3', {}, _('Logs')),
			E('div', { class: 'cbi-section-buttons' }, [
				E('button', {
					class: 'btn cbi-button cbi-button-action',
					click: function() {
						return api.logTail(200).then(function(r) {
							pre.textContent = (r && r.text) || _('No log output.');
						});
					}
				}, _('Refresh')),
				E('button', {
					class: 'btn cbi-button cbi-button-negative',
					click: function() {
						return api.logClear().then(function() {
							pre.textContent = '';
							ui.addNotification(_('Logs'), _('Cleared'), 'info');
						});
					}
				}, _('Clear'))
			]),
			pre
		]);
	}
});
