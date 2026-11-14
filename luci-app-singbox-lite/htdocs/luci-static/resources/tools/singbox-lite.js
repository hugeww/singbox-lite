'use strict';

'require baseclass';
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

return baseclass.extend({
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
	rulesetUpdate: (id) => callRulesetUpdate(id || null),
	logTail: (lines) => callLogTail(lines || 100),
	logClear: () => callLogClear(),
	yqStatus: () => callYqStatus(),
	installYq: () => callInstallYq()
});
