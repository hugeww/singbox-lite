'use strict';

'require view';
'require poll';
'require ui';
'require tools.singbox-lite as api';

function fmtBytes(n) {
	n = Number(n) || 0;
	if (n < 1024) return n + ' B';
	if (n < 1048576) return (n / 1024).toFixed(1) + ' KB';
	if (n < 1073741824) return (n / 1048576).toFixed(1) + ' MB';
	return (n / 1073741824).toFixed(2) + ' GB';
}

function notify(title, msg, type) {
	ui.addNotification(title, msg, type || 'info');
}

function urlHost() {
	let host = window.location.hostname || '127.0.0.1';
	if (host.indexOf(':') >= 0 && host.charAt(0) != '[')
		host = '[' + host + ']';
	return host;
}

function backendUrl(port) {
	return 'http://' + urlHost() + ':' + (port || 9090);
}

function dashboardUrl(port) {
	return backendUrl(port) + '/dashboard/';
}

function copyButton(text) {
	let btn = E('button', { class: 'btn cbi-button' }, _('Copy'));
	btn.addEventListener('click', function() {
		if (!navigator.clipboard || !navigator.clipboard.writeText) return;
		navigator.clipboard.writeText(text).then(function() {
			notify(_('Panel'), _('Copied'), 'info');
		});
	});
	return btn;
}

function renderOfficial(status, title, descr) {
	let url = dashboardUrl(status.port);

	if (!status.dashboard_installed) {
		let btn = E('button', { class: 'btn cbi-button cbi-button-positive' }, _('Download dashboard files'));
		btn.addEventListener('click', function() {
			btn.disabled = true;
			api.dashboardUpdate().then(function(r) {
				if (!r || !r.ok) {
					btn.disabled = false;
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
							window.location.reload();
						} else if (state == 'error') {
							clearInterval(timer);
							btn.disabled = false;
							notify(_('Panel'), (st && st.error) || _('Action failed'), 'danger');
						} else if (++tries > 150) {
							clearInterval(timer);
							btn.disabled = false;
						}
					}).catch(function() {
						clearInterval(timer);
						btn.disabled = false;
					});
				}, 2000);
			});
		});
		return E('div', { class: 'cbi-map' }, [
			title,
			descr,
			E('fieldset', { class: 'cbi-section' }, [
				E('p', {}, _('Dashboard files are not installed yet. Download them, then save the configuration and restart the service.')),
				E('p', {}, btn)
			])
		]);
	}

	if (!status.ok) {
		return E('div', { class: 'cbi-map' }, [
			title,
			descr,
			E('fieldset', { class: 'cbi-section' }, [
				E('p', {}, status.enabled === true
					? _('sing-box API is not reachable. Save the configuration and restart the service.')
					: _('Panel is disabled. Enable it in Settings and restart the service.')),
				E('p', {}, (status.port ? _('Port') + ': ' + status.port + '  ' : '') +
					(status.error ? _('Error') + ': ' + status.error : '')),
				E('a', {
					class: 'btn cbi-button cbi-button-action',
					href: L.url('admin/services/singbox-lite/settings')
				}, _('Go to Settings'))
			])
		]);
	}

	let secret = status.secret || '';
	let listen = status.listen || '';
	let backend = backendUrl(status.port);
	let loopback = (listen == '127.0.0.1' || listen == '::1' || listen == '[::1]');

	let info = E('fieldset', { class: 'cbi-section' }, [
		E('div', { class: 'cbi-value' }, [
			E('label', { class: 'cbi-value-title' }, _('Panel address')),
			E('div', { class: 'cbi-value-field' }, E('a', { href: url, target: '_blank', rel: 'noopener' }, url))
		]),
		E('div', { class: 'cbi-value' }, [
			E('label', { class: 'cbi-value-title' }, _('Backend API URL')),
			E('div', { class: 'cbi-value-field' }, E('code', {}, backend))
		]),
		E('div', { class: 'cbi-value' }, [
			E('label', { class: 'cbi-value-title' }, _('API secret')),
			E('div', { class: 'cbi-value-field' }, [ E('code', {}, secret || '-'), ' ', copyButton(secret) ])
		]),
		E('p', {}, _('In the dashboard settings, enter the backend API URL and this secret once.')),
		loopback ? E('p', {}, E('strong', {}, _('The official dashboard is only reachable from other devices when the sing-box API listens on 0.0.0.0 or a LAN address.'))) : ''
	]);

	return E('div', { class: 'cbi-map' }, [
		title,
		descr,
		info,
		E('fieldset', { class: 'cbi-section' }, E('iframe', {
			src: url,
			style: 'width:100%;height:78vh;border:0;background:#fff;'
		}))
	]);
}

return view.extend({
	load: function() {
		return api.panelStatus().catch(function() { return null; }).then(function(status) {
			/* The official dashboard is served by the sing-box API; there is no
			   Clash API to query in that mode. Skip the proxy probe entirely. */
			if (status && status.dashboard === 'official')
				return [ status, null ];
			return Promise.all([
				Promise.resolve(status),
				api.panelProxies().catch(function() { return null; })
			]);
		});
	},

	render: function(data) {
		let status = (data && data[0]) || {};
		let proxies = (data && data[1]) || {};
		let self = this;

		let title = E('h2', { name: 'content' }, _('Panel'));
		let descr = E('div', { class: 'cbi-map-descr' },
			status.dashboard === 'official'
				? _('Official sing-box dashboard served by the sing-box API.')
				: _('Live status, proxy groups and connections from the sing-box Clash API.'));

		if (status.dashboard === 'official')
			return renderOfficial(status, title, descr);

		if (!status.ok) {
			let enabled = status.enabled === true;
			let message = enabled
				? _('Clash API is not reachable. Save the configuration and restart the service.')
				: _('Panel is disabled. Enable it in Settings and restart the service.');
			return E('div', { class: 'cbi-map' }, [
				title,
				descr,
				E('fieldset', { class: 'cbi-section' }, [
					E('p', {}, message),
					E('p', {}, (status.port ? _('Port') + ': ' + status.port + '  ' : '') +
						(status.error ? _('Error') + ': ' + status.error : '')),
					E('a', {
						class: 'btn cbi-button cbi-button-action',
						href: L.url('admin/services/singbox-lite/settings')
					}, _('Go to Settings'))
				])
			]);
		}

		let elCore = E('span', {}, status.version || '-');
		let elMode = E('span', {}, status.mode || '-');
		let elUp = E('span', {}, fmtBytes(status.upload));
		let elDown = E('span', {}, fmtBytes(status.download));
		let elCount = E('span', {}, String(status.count || 0));

		let statusSection = E('fieldset', { class: 'cbi-section' }, [
			E('legend', {}, _('Status')),
			E('div', { class: 'cbi-value' }, [
				E('label', { class: 'cbi-value-title' }, _('Core version')),
				E('div', { class: 'cbi-value-field' }, elCore)
			]),
			E('div', { class: 'cbi-value' }, [
				E('label', { class: 'cbi-value-title' }, _('Mode')),
				E('div', { class: 'cbi-value-field' }, elMode)
			]),
			E('div', { class: 'cbi-value' }, [
				E('label', { class: 'cbi-value-title' }, _('Upload')),
				E('div', { class: 'cbi-value-field' }, elUp)
			]),
			E('div', { class: 'cbi-value' }, [
				E('label', { class: 'cbi-value-title' }, _('Download')),
				E('div', { class: 'cbi-value-field' }, elDown)
			]),
			E('div', { class: 'cbi-value' }, [
				E('label', { class: 'cbi-value-title' }, _('Active connections')),
				E('div', { class: 'cbi-value-field' }, elCount)
			])
		]);

		let backend = backendUrl(status.port);
		let apiSection = E('fieldset', { class: 'cbi-section' }, [
			E('legend', {}, _('API')),
			E('div', { class: 'cbi-value' }, [
				E('label', { class: 'cbi-value-title' }, _('Backend API URL')),
				E('div', { class: 'cbi-value-field' }, E('code', {}, backend))
			]),
			E('div', { class: 'cbi-value' }, [
				E('label', { class: 'cbi-value-title' }, _('API secret')),
				E('div', { class: 'cbi-value-field' }, [ E('code', {}, status.secret || '-'), ' ', copyButton(status.secret || '') ])
			]),
			E('p', {}, _('Use this URL and secret for a third-party Clash dashboard.'))
		]);

		let proxyBox = E('div', {});
		let connBox = E('div', {});

		function renderGroups(groups, delays) {
			delays = delays || {};
			while (proxyBox.firstChild) proxyBox.removeChild(proxyBox.firstChild);
			if (!groups || !groups.length) {
				proxyBox.appendChild(E('p', {}, _('No proxy groups yet.')));
				return;
			}
			groups.forEach(function(g) {
				let picker;
				if (g.type == 'selector' || g.type == 'fallback') {
					picker = E('select', { class: 'cbi-input-select' });
					(g.members || []).forEach(function(m) {
						let label = m.name;
						let d = delays[g.name] && delays[g.name][m.name] !== undefined ? delays[g.name][m.name] : m.delay;
						if (d > 0) label += ' (' + d + ' ms)';
						picker.appendChild(E('option', {
							value: m.name,
							selected: m.name == g.now ? 'selected' : null
						}, label));
					});
					picker.addEventListener('change', function() {
						api.panelSelect(g.name, picker.value).then(function(r) {
							notify(_('Proxy group'), r && r.ok ? _('Selected node') + ': ' + picker.value : ((r && r.error) || _('Selection failed')), r && r.ok ? 'info' : 'danger');
						});
					});
				} else {
					picker = E('span', {}, g.now || '-');
				}
				let btn = E('button', { class: 'btn cbi-button cbi-button-action' }, _('Test latency'));
				btn.addEventListener('click', function() {
					btn.disabled = true;
					api.panelDelay(g.name).then(function(r) {
						btn.disabled = false;
						if (r && r.ok) renderGroups(groups, { [g.name]: r.delays });
						else notify(_('Proxy group'), (r && r.error) || _('Test failed'), 'danger');
					});
				});
				proxyBox.appendChild(E('div', { class: 'cbi-value' }, [
					E('label', { class: 'cbi-value-title' }, g.name + ' (' + g.type + ')'),
					E('div', { class: 'cbi-value-field' }, [picker, ' ', btn])
				]));
			});
		}

		function renderConnections(list) {
			while (connBox.firstChild) connBox.removeChild(connBox.firstChild);
			let rows = (list && list.connections) || [];
			if (!rows.length) {
				connBox.appendChild(E('p', {}, _('No active connections.')));
				return;
			}
			let tbody = E('tbody', {});
			rows.forEach(function(c) {
				tbody.appendChild(E('tr', { class: 'tr' }, [
					E('td', { class: 'td' }, c.host || c.dest || '-'),
					E('td', { class: 'td' }, c.rule || '-'),
					E('td', { class: 'td' }, (c.chains || []).join(' → ') || '-'),
					E('td', { class: 'td' }, c.network || '-'),
					E('td', { class: 'td' }, fmtBytes(c.upload)),
					E('td', { class: 'td' }, fmtBytes(c.download)),
					E('td', { class: 'td' }, E('button', {
						class: 'btn cbi-button cbi-button-remove',
						click: function() {
							api.panelClose(c.id).then(function(r) {
								notify(_('Connections'), r && r.ok ? _('Connection closed') : ((r && r.error) || _('Action failed')), r && r.ok ? 'info' : 'danger');
							});
						}
					}, _('Close')))
				]));
			});
			connBox.appendChild(E('table', { class: 'table' }, [
				E('thead', {}, E('tr', { class: 'tr table-titles' }, [
					E('th', { class: 'th' }, _('Host')),
					E('th', { class: 'th' }, _('Rule')),
					E('th', { class: 'th' }, _('Chain')),
					E('th', { class: 'th' }, _('Network')),
					E('th', { class: 'th' }, _('Upload')),
					E('th', { class: 'th' }, _('Download')),
					E('th', { class: 'th' }, '')
				])),
				tbody
			]));
		}

		renderGroups(proxies.groups || [], {});

		let proxySection = E('fieldset', { class: 'cbi-section' }, [
			E('legend', {}, _('Proxy groups')),
			proxyBox
		]);
		let connSection = E('fieldset', { class: 'cbi-section' }, [
			E('legend', {}, _('Connections')),
			connBox
		]);

		poll.add(function() {
			return Promise.all([
				api.panelStatus().catch(function() { return null; }),
				api.panelConnections(30).catch(function() { return null; })
			]).then(function(res) {
				let st = res[0] || {};
				if (st.ok) {
					elCore.textContent = st.version || '-';
					elMode.textContent = st.mode || '-';
					elUp.textContent = fmtBytes(st.upload);
					elDown.textContent = fmtBytes(st.download);
					elCount.textContent = String(st.count || 0);
				}
				renderConnections(res[1] || {});
			});
		}, 5);

		poll.add(function() {
			return api.panelProxies().then(function(r) {
				if (r && r.ok) renderGroups(r.groups || [], {});
			}).catch(function() {});
		}, 15);

		return E('div', { class: 'cbi-map' }, [ title, descr, statusSection, apiSection, proxySection, connSection ]);
	}
});
