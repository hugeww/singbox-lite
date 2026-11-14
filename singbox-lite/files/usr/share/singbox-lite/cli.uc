'use strict';

import { trim, read_text, read_json, write_text, write_json, mkdir_p, file_exists, run_capture, now_string, human_size, sh_quote, PATH, VERSION, split_lines } from 'sbx_common';
import { load_config, uci_set, uci_commit } from 'sbx_config';
import { collect_nodes, group_nodes } from 'sbx_nodes';
import { build_config } from 'sbx_generator';
import { fetch_subscription } from 'sbx_subs';
import { update_ruleset, update_builtin_rulesets } from 'sbx_rulesets';
import { core_path, core_status, update_core, rollback_core, MIN_VERSION, version_ge, latest_tag, arch_asset, download_url } from 'sbx_core';
import { plugin_status, plugin_check, update_plugin, PLUGIN_REPO } from 'sbx_plugin';
import { list_tags, cache_read, cache_write } from 'sbx_releases';
import { panel_status, panel_proxies, panel_select, panel_delay, panel_connections, panel_close, random_secret, dashboard_status, update_dashboard } from 'sbx_panel';
import { unlink, rename, dirname } from 'fs';
import { parse_link } from 'sbx_links';

function output(obj) {
	print(sprintf('%J', obj));
	print('\n');
}

function parse_args(argv) {
	let opts = { _: [] };
	for (let i = 0; i < length(argv); i++) {
		let a = argv[i];
		if (substr(a, 0, 2) == '--') {
			let key = substr(a, 2);
			if (key == 'json' || key == 'all' || key == 'no-restart' || key == 'dry-run') {
				opts[key] = true;
			} else if (i + 1 < length(argv)) {
				opts[key] = argv[++i];
			} else {
				opts[key] = true;
			}
		} else {
			push(opts._, a);
		}
	}
	return opts;
}

function service_running() {
	if (!file_exists('/var/run/singbox-lite.pid')) return false;
	let pid = trim(read_text('/var/run/singbox-lite.pid', ''));
	if (!length(pid)) return false;
	return system(['kill', '-0', pid]) == 0;
}

function service_pid() {
	return trim(read_text('/var/run/singbox-lite.pid', ''));
}

function generate(cfg) {
	let collected = collect_nodes(cfg);
	let gen = build_config(cfg, collected);
	if (!gen.ok) return { ok: false, errors: gen.errors || [], warnings: gen.warnings || [] };
	return { ok: true, config: gen.config, warnings: gen.warnings || [], collected: collected };
}

function check_core(cfg) {
	let path = core_path(cfg);
	let version = null;
	let r = run_capture(sh_quote(path) + ' version 2>/dev/null');
	if (r.ok) {
		let m = match(r.out, /sing-box version ([0-9]+\.[0-9]+\.[0-9]+)/);
		if (m) version = m[1];
	}
	if (!version) return { ok: false, error: '未找到可执行的 sing-box 核心，请先安装/更新核心', path: path };
	if (!version_ge(version, MIN_VERSION)) return { ok: false, error: '核心版本 ' + version + ' 低于最低要求 ' + MIN_VERSION, path: path };
	return { ok: true, path: path, version: version };
}

function check_config_with(core, file) {
	let r = run_capture(sh_quote(core) + ' check -c ' + sh_quote(file) + ' 2>&1');
	return { ok: r.ok, output: trim(r.out) };
}

function save_config(cfg, gen) {
	let core = check_core(cfg);
	if (!core.ok) return core;
	mkdir_p(PATH.etc);
	let tmp = PATH.config_json + '.tmp';
	let json = sprintf('%J', gen.config);
	if (!write_text(tmp, json, 384)) return { ok: false, error: '写入临时配置失败' };
	let chk = check_config_with(core.path, tmp);
	if (!chk.ok) {
		try { unlink(tmp); } catch (e) {}
		return { ok: false, error: '配置校验失败', detail: chk.output };
	}
	if (file_exists(PATH.config_json))
		run_capture('cp ' + sh_quote(PATH.config_json) + ' ' + sh_quote(PATH.config_bak));
	if (rename(tmp, PATH.config_json) !== true) {
		try { unlink(tmp); } catch (e) {}
		return { ok: false, error: '替换配置失败' };
	}
	return { ok: true, bytes: length(json), warnings: gen.warnings };
}

function sync_cron(cfg) {
	if (getenv('SINGBOX_LITE_CONFIG_JSON') != null)
		return;
	let main = cfg.main || {};
	let marker = '# singbox-lite';
	let lines = split(read_text(PATH.cron_file, ''), '\n');
	let out = [];
	for (let line in lines) {
		line = rtrim(line);
		if (!length(line)) continue;
		if (match(line, /# singbox-lite$/)) continue;
		push(out, line);
	}
	if (main.auto_update != '0') {
		let hours = int(main.update_interval || 6);
		if (hours < 1) hours = 1;
		if (hours > 23) hours = 23;
		push(out, '0 */' + hours + ' * * * /usr/bin/singbox-lite refresh --all --json >>/var/log/singbox-lite/refresh.log 2>&1 ' + marker);
	}
	mkdir_p(dirname(PATH.cron_file));
	let text = '';
	for (let line in out) text += line + '\n';
	write_text(PATH.cron_file, text, 384);
	run_capture('/etc/init.d/cron reload >/dev/null 2>&1 || true');
}
function ensure_panel_secret(cfg) {
	if (!cfg.panel) cfg.panel = {};
	if (cfg.panel.enabled != '1') return false;
	if (length(trim(cfg.panel.secret || ''))) return false;
	let secret = random_secret();
	cfg.panel.secret = secret;
	if (getenv('SINGBOX_LITE_CONFIG_JSON') == null) {
		uci_set('panel', 'secret', secret);
		uci_commit();
	}
	return true;
}

function cmd_check(cfg) {
	ensure_panel_secret(cfg);
	let gen = generate(cfg);
	if (!gen.ok) return { ok: false, errors: gen.errors, warnings: gen.warnings };
	let saved = save_config(cfg, gen);
	if (!saved.ok)
		return { ok: false, error: saved.error || '配置校验失败', detail: saved.detail || '', errors: [ saved.error || '配置校验失败' ], warnings: gen.warnings };
	sync_cron(cfg);
	let core = core_status(cfg);
	return { ok: true, error: null, detail: '', warnings: gen.warnings, core: core.version || '' };
}

function cmd_build(cfg, opts) {
	ensure_panel_secret(cfg);
	let gen = generate(cfg);
	if (!gen.ok) return { ok: false, errors: gen.errors, warnings: gen.warnings };
	if (opts['dry-run']) return { ok: true, config: gen.config, warnings: gen.warnings };
	let saved = save_config(cfg, gen);
	if (saved.ok) sync_cron(cfg);
	return saved;
}

function cmd_refresh(cfg, opts) {
	ensure_panel_secret(cfg);
	let updated = 0, failed = 0, results = [];
	let only = opts.id || null;
	for (let sub in cfg.subscriptions) {
		if (sub.enabled == '0') continue;
		if (only && sub['.name'] != only) continue;
		let r = fetch_subscription(sub['.name'], sub.url || '', sub.ua || 'sing-box/1.14', sub.format || 'auto');
		if (r.ok) {
			updated++;
			if (getenv('SINGBOX_LITE_CONFIG_JSON') == null) {
				uci_set(sub['.name'], 'status', 'ok');
				uci_set(sub['.name'], 'last_update', now_string());
				uci_set(sub['.name'], 'error', '');
				if (r.userinfo && r.userinfo.expire_text) uci_set(sub['.name'], 'expire', r.userinfo.expire_text);
				if (r.userinfo && r.userinfo.used != null) uci_set(sub['.name'], 'used', human_size(r.userinfo.used));
				if (r.userinfo && r.userinfo.total != null) uci_set(sub['.name'], 'total', human_size(r.userinfo.total));
			}
			push(results, { section: sub['.name'], ok: true, nodes: length(r.nodes), warnings: r.warnings });
		} else {
			failed++;
			if (getenv('SINGBOX_LITE_CONFIG_JSON') == null) {
				uci_set(sub['.name'], 'status', 'error');
				uci_set(sub['.name'], 'last_update', now_string());
				uci_set(sub['.name'], 'error', substr(r.error || '更新失败', 0, 200));
			}
			push(results, { section: sub['.name'], ok: false, error: r.error });
		}
	}
	if (getenv('SINGBOX_LITE_CONFIG_JSON') == null && (updated || failed))
		uci_commit();

	let gen = generate(cfg);
	let status = {
		ok: gen.ok, updated: updated, failed: failed, results: results,
		warnings: gen.warnings || [], errors: gen.errors || []
	};
	if (gen.ok) {
		let saved = save_config(cfg, gen);
		if (!saved.ok) {
			status.ok = false;
			status.errors = [ saved.error || '保存配置失败' ];
		} else {
			sync_cron(cfg);
			if (service_running() && opts['no-restart'] != true && cfg.main.auto_apply != '0') {
				let rc = system([PATH.init, 'restart']);
				sleep(3);
				status.restarted = (rc == 0 && service_running());
			}
		}
	}
	mkdir_p(PATH.run_dir);
	write_json(PATH.refresh_status, status, 384);
	return status;
}

function cmd_status(cfg) {
	let collected = collect_nodes(cfg);
	let groups = group_nodes(collected.nodes);
	let core = core_status(cfg);
	let subs = [];
	for (let sub in cfg.subscriptions) {
		push(subs, {
			section: sub['.name'], name: sub.name || sub['.name'],
			enabled: sub.enabled != '0', status: sub.status || 'never',
			last_update: sub.last_update || '', expire: sub.expire || '',
			used: sub.used || '', total: sub.total || '', error: sub.error || ''
		});
	}
	let node_list = [];
	for (let n in collected.nodes) push(node_list, { id: n.id, name: n.name, type: n.type, server: n.server, port: n.server_port, country: n.country, country_mode: n.country_mode || 'auto', native: n.native, native_mode: n.native_mode || 'auto', source: n.source_name });
	let cfg_hash = '';
	if (file_exists(PATH.config_json)) {
		let r = run_capture('sha256sum ' + sh_quote(PATH.config_json) + ' 2>/dev/null');
		cfg_hash = trim(split(r.out, ' ')[0] || '');
	}
	let active_hash = trim(read_text('/var/run/singbox-lite.active.hash', ''));
	let pending = service_running() && length(active_hash) && length(cfg_hash) && active_hash != cfg_hash;
	return {
		ok: true, version: VERSION, running: service_running(), pid: service_pid(),
		core: core, plugin: plugin_status(), config_exists: file_exists(PATH.config_json), pending: pending,
		nodes: length(collected.nodes), groups: {
			us: length(groups.us), jp: length(groups.jp), hk: length(groups.hk),
			other: length(groups.other), native: length(groups.native), auto: length(groups.auto)
		},
		subscriptions: subs, node_list: node_list, warnings: collected.warnings,
		last_refresh: read_json(PATH.refresh_status, null)
	};
}

function cmd_update_rulesets(cfg, opts) {
	if (opts.id) return update_ruleset(cfg, opts.id);
	return update_builtin_rulesets((cfg.main && cfg.main.core_mirror) || '');
}

function cmd_log(opts) {
	let lines = int(opts.lines || 100);
	let out = '';
	for (let file in [ PATH.log_dir + '/core.log', PATH.log_dir + '/app.log' ]) {
		let text = read_text(file, '');
		if (!length(text)) continue;
		let arr = split(text, '\n');
		let start = length(arr) > lines ? length(arr) - lines : 0;
		out += '=== ' + file + ' ===\n';
		for (let i = start; i < length(arr); i++) out += arr[i] + '\n';
	}
	return { ok: true, text: out };
}

function cmd_release_scan(cfg) {
	let mirror = (cfg && cfg.main && cfg.main.core_mirror) || '';
	let core = list_tags('SagerNet/sing-box', mirror, 10);
	let plugin = list_tags(PLUGIN_REPO, mirror, 10);
	let cached = cache_read();
	let out = {
		ok: core.ok || plugin.ok,
		core: core.ok ? core.tags : (cached.core || []),
		plugin: plugin.ok ? plugin.tags : (cached.plugin || []),
		core_ok: core.ok,
		plugin_ok: plugin.ok,
		error: (!core.ok && !plugin.ok) ? (core.error || plugin.error) : null
	};
	cache_write(out);
	return out;
}

function main() {
	let argv = ARGV;
	let cmd = argv[0] || 'help';
	let opts = parse_args(slice(argv, 1));
	let cfg = null;
	try {
		if (cmd == 'version') return output({ ok: true, version: VERSION });
		if (cmd == 'help') return output({ ok: true, commands: [ 'preview', 'check', 'build', 'refresh', 'status', 'update-rulesets', 'update-core', 'update-plugin', 'core-check', 'core-rollback', 'plugin-status', 'plugin-check', 'release-scan', 'panel-status', 'panel-proxies', 'panel-connections', 'panel-select', 'panel-delay', 'panel-close', 'panel-secret', 'dashboard-status', 'update-dashboard', 'parse-link', 'log' ] });
		if (cmd == 'parse-link') {
			let p = parse_link(opts._[0] || '');
			return output(p);
		}
		if (cmd == 'core-rollback') return output(rollback_core());
		if (cmd == 'plugin-status') return output(plugin_status());
		if (cmd == 'core-check') {
			try { cfg = load_config(); } catch (e) {}
			let l = latest_tag((cfg && cfg.main && cfg.main.core_mirror) || '');
			if (!l.ok) return output(l);
			let asset = arch_asset();
			if (!asset) return output({ ok: false, error: '当前架构没有可用资产' });
			let dl = download_url(l.tag, asset, (cfg && cfg.main && cfg.main.core_mirror) || '');
			return output({ ok: true, tag: l.tag, asset: asset, url: dl.url, version: dl.version });
		}
		cfg = load_config();
		if (cmd == 'plugin-check') return output(plugin_check(cfg));
		if (cmd == 'release-scan') return output(cmd_release_scan(cfg));
		if (cmd == 'update-plugin') return output(update_plugin(cfg, opts));
		if (cmd == 'panel-status') return output(panel_status(cfg));
		if (cmd == 'dashboard-status') return output(dashboard_status(cfg));
		if (cmd == 'update-dashboard') return output(update_dashboard(cfg, opts));
		if (cmd == 'panel-proxies') return output(panel_proxies(cfg));
		if (cmd == 'panel-connections') return output(panel_connections(cfg, int(opts.limit || 30)));
		if (cmd == 'panel-select') return output(panel_select(cfg, opts.group || '', opts.node || ''));
		if (cmd == 'panel-delay') return output(panel_delay(cfg, opts.group || ''));
		if (cmd == 'panel-close') return output(panel_close(cfg, opts.id || ''));
		if (cmd == 'panel-secret') {
			let secret = random_secret();
			if (getenv('SINGBOX_LITE_CONFIG_JSON') == null) {
				uci_set('panel', 'secret', secret);
				uci_commit();
			}
			return output({ ok: true, secret: secret });
		}
		if (cmd == 'preview') {
			let gen = generate(cfg);
			if (!gen.ok) return output({ ok: false, errors: gen.errors, warnings: gen.warnings });
			return output({ ok: true, config: gen.config, warnings: gen.warnings });
		}
		if (cmd == 'check') return output(cmd_check(cfg));
		if (cmd == 'build') return output(cmd_build(cfg, opts));
		if (cmd == 'refresh') return output(cmd_refresh(cfg, opts));
		if (cmd == 'status') return output(cmd_status(cfg));
		if (cmd == 'update-rulesets') return output(cmd_update_rulesets(cfg, opts));
		if (cmd == 'update-core') return output(update_core(cfg, opts));
		if (cmd == 'log') return output(cmd_log(opts));
		return output({ ok: false, error: 'unknown command: ' + cmd });
	} catch (e) {
		return output({ ok: false, error: 'exception: ' + e });
	}
}

main();
