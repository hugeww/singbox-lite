'use strict';

'require baseclass';
'require form';
'require rpc';

const callStatus = rpc.declare({
	object: 'luci.singbox_lite', method: 'status', expect: { '': {} }
});
const callConfigPreview = rpc.declare({
	object: 'luci.singbox_lite', method: 'config_preview', expect: { '': {} }
});
const callConfigCheck = rpc.declare({
	object: 'luci.singbox_lite', method: 'config_check', expect: { '': {} }
});
const callConfigSave = rpc.declare({
	object: 'luci.singbox_lite', method: 'config_save', expect: { '': {} }
});
const callServiceControl = rpc.declare({
	object: 'luci.singbox_lite', method: 'service_control', params: [ 'action' ], expect: { '': {} }
});
const callSubscriptionUpdate = rpc.declare({
	object: 'luci.singbox_lite', method: 'subscription_update', params: [ 'section' ], expect: { '': {} }
});
const callSubscriptionUpdateAll = rpc.declare({
	object: 'luci.singbox_lite', method: 'subscription_update_all', expect: { '': {} }
});
const callSubscriptionStatus = rpc.declare({
	object: 'luci.singbox_lite', method: 'subscription_status', expect: { '': {} }
});
const callNodeParse = rpc.declare({
	object: 'luci.singbox_lite', method: 'node_parse', params: [ 'links' ], expect: { '': {} }
});
const callEgressStatus = rpc.declare({
	object: 'luci.singbox_lite', method: 'egress_status', expect: { '': {} }
});
const callCoreStatus = rpc.declare({
	object: 'luci.singbox_lite', method: 'core_status', expect: { '': {} }
});
const callCoreCheckLatest = rpc.declare({
	object: 'luci.singbox_lite', method: 'core_check_latest', expect: { '': {} }
});
const callCoreUpdate = rpc.declare({
	object: 'luci.singbox_lite', method: 'core_update', params: [ 'version', 'asset', 'mirror' ], expect: { '': {} }
});
const callCoreUpdateStatus = rpc.declare({
	object: 'luci.singbox_lite', method: 'core_update_status', expect: { '': {} }
});
const callCoreRollback = rpc.declare({
	object: 'luci.singbox_lite', method: 'core_rollback', expect: { '': {} }
});
const callReleaseList = rpc.declare({
	object: 'luci.singbox_lite', method: 'release_list', expect: { '': {} }
});
const callReleaseScan = rpc.declare({
	object: 'luci.singbox_lite', method: 'release_scan', expect: { '': {} }
});
const callPluginStatus = rpc.declare({
	object: 'luci.singbox_lite', method: 'plugin_status', expect: { '': {} }
});
const callPluginCheck = rpc.declare({
	object: 'luci.singbox_lite', method: 'plugin_check', expect: { '': {} }
});
const callPluginUpdate = rpc.declare({
	object: 'luci.singbox_lite', method: 'plugin_update', params: [ 'version', 'mirror' ], expect: { '': {} }
});
const callPluginUpdateStatus = rpc.declare({
	object: 'luci.singbox_lite', method: 'plugin_update_status', expect: { '': {} }
});
const callPanelStatus = rpc.declare({
	object: 'luci.singbox_lite', method: 'panel_status', expect: { '': {} }
});
const callPanelProxies = rpc.declare({
	object: 'luci.singbox_lite', method: 'panel_proxies', expect: { '': {} }
});
const callPanelConnections = rpc.declare({
	object: 'luci.singbox_lite', method: 'panel_connections', params: [ 'limit' ], expect: { '': {} }
});
const callPanelSelect = rpc.declare({
	object: 'luci.singbox_lite', method: 'panel_select', params: [ 'group', 'node' ], expect: { '': {} }
});
const callPanelDelay = rpc.declare({
	object: 'luci.singbox_lite', method: 'panel_delay', params: [ 'group' ], expect: { '': {} }
});
const callPanelClose = rpc.declare({
	object: 'luci.singbox_lite', method: 'panel_close', params: [ 'id' ], expect: { '': {} }
});
const callPanelSecret = rpc.declare({
	object: 'luci.singbox_lite', method: 'panel_secret', expect: { '': {} }
});
const callDashboardStatus = rpc.declare({
	object: 'luci.singbox_lite', method: 'dashboard_status', expect: { '': {} }
});
const callDashboardUpdate = rpc.declare({
	object: 'luci.singbox_lite', method: 'dashboard_update', expect: { '': {} }
});
const callDashboardUpdateStatus = rpc.declare({
	object: 'luci.singbox_lite', method: 'dashboard_update_status', expect: { '': {} }
});
const callRulesetUpdate = rpc.declare({
	object: 'luci.singbox_lite', method: 'ruleset_update', params: [ 'id' ], expect: { '': {} }
});
const callLogTail = rpc.declare({
	object: 'luci.singbox_lite', method: 'log_tail', params: [ 'lines' ], expect: { '': {} }
});
const callLogClear = rpc.declare({
	object: 'luci.singbox_lite', method: 'log_clear', expect: { '': {} }
});
const callYqStatus = rpc.declare({
	object: 'luci.singbox_lite', method: 'yq_status', expect: { '': {} }
});
const callInstallYq = rpc.declare({
	object: 'luci.singbox_lite', method: 'install_yq', expect: { '': {} }
});

/*
 * Anonymous action/status table that is guaranteed to render a row.
 *
 * LuCI renders one table row per uci section of `sectiontype`. A made-up
 * section type such as 'placeholder' has no backing section, so newer LuCI
 * releases (observed with luci-base 26.249) produce zero rows and fall back
 * to "This section contains no values yet", leaving the whole page blank.
 * Binding the table to a section that always exists (default: 'main') keeps
 * it working on both the old and the new LuCI rendering path, because
 * DummyValue/Button options do not need real config data.
 */
function actionTable(map, title, sectiontype) {
	const s = map.section(form.TableSection, sectiontype || 'main', title);
	s.anonymous = true;
	return s;
}

return baseclass.extend({
	actionTable: (map, title, sectiontype) => actionTable(map, title, sectiontype),
	status: () => callStatus(),
	configPreview: () => callConfigPreview(),
	configCheck: () => callConfigCheck(),
	configSave: () => callConfigSave(),
	serviceControl: (action) => callServiceControl(action),
	subscriptionUpdate: (section) => callSubscriptionUpdate(section),
	subscriptionUpdateAll: () => callSubscriptionUpdateAll(),
	subscriptionStatus: () => callSubscriptionStatus(),
	nodeParse: (links) => callNodeParse(links),
	egressStatus: () => callEgressStatus(),
	coreStatus: () => callCoreStatus(),
	coreCheckLatest: () => callCoreCheckLatest(),
	coreUpdate: (version, asset, mirror) => callCoreUpdate(version || null, asset || null, mirror || null),
	coreUpdateStatus: () => callCoreUpdateStatus(),
	coreRollback: () => callCoreRollback(),
	releaseList: () => callReleaseList(),
	releaseScan: () => callReleaseScan(),
	pluginStatus: () => callPluginStatus(),
	pluginCheck: () => callPluginCheck(),
	pluginUpdate: (version, mirror) => callPluginUpdate(version || null, mirror || null),
	pluginUpdateStatus: () => callPluginUpdateStatus(),
	panelStatus: () => callPanelStatus(),
	panelProxies: () => callPanelProxies(),
	panelConnections: (limit) => callPanelConnections(limit || 30),
	panelSelect: (group, node) => callPanelSelect(group, node),
	panelDelay: (group) => callPanelDelay(group),
	panelClose: (id) => callPanelClose(id),
	panelSecret: () => callPanelSecret(),
	dashboardStatus: () => callDashboardStatus(),
	dashboardUpdate: () => callDashboardUpdate(),
	dashboardUpdateStatus: () => callDashboardUpdateStatus(),
	rulesetUpdate: (id) => callRulesetUpdate(id || null),
	logTail: (lines) => callLogTail(lines || 100),
	logClear: () => callLogClear(),
	yqStatus: () => callYqStatus(),
	installYq: () => callInstallYq()
});
