'use strict';

import { trim, read_text, read_json, write_text, write_json, mkdir_p, file_exists, run_capture, now_string, human_size, sh_quote, log_app, PATH, VERSION, split_lines } from 'sbx_common';
import { load_config, uci_set, uci_commit } from 'sbx_config';
import { collect_nodes, group_nodes } from 'sbx_nodes';
import { build_config } from 'sbx_generator';
import { fetch_subscription } from 'sbx_subs';
import { update_ruleset, update_builtin_rulesets } from 'sbx_rulesets';
import { core_path, core_status, update_core, rollback_core, MIN_VERSION, version_ge, latest_tag, arch_asset, download_url } from 'sbx_core';
import { plugin_status, plugin_check, update_plugin, PLUGIN_REPO } from 'sbx_plugin';
import { list_tags, cache_read, cache_write } from 'sbx_releases';
import { panel_status, panel_proxies, panel_select, panel_delay, panel_connections, panel_close, random_secret, dashboard_status, update_dashboard } from 'sbx_panel';
import { unlink, rename, dirname, mkdir, rmdir, stat } from 'fs';
import { parse_link } from 'sbx_links';

/* Mutating commands are serialised with a portable lock (path based, no flock:
   OpenWrt/busybox does not guarantee util-linux flock). PATH.lock is a
   directory, created atomically with mkdir(); its owner file records
   "<pid> <epoch>" so a crashed run can be detected and stolen safely. */
const LOCK_WAIT_SECONDS = 10;
const LOCK_STALE_SECONDS = 30 * 60;
/* 状态/日志中 detail 的最大长度：足够定位问题，又不会把 JSON 或 app.log 撑爆。 */
const POST_UPGRADE_DETAIL_LIMIT = 2000;

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

function self_pid() {
	let m = match(read_text('/proc/self/stat', ''), /^([0-9]+)/);
	return m ? int(m[1]) : 0;
}

function read_lock_owner() {
	let m = match(trim(read_text(PATH.lock + '/owner', '')), /^([0-9]+)[ \t]+([0-9]+)/);
	if (!m) return { pid: 0, ts: 0 };
	return { pid: int(m[1]), ts: int(m[2]) };
}

function pid_alive(pid) {
	if (!pid || pid <= 0) return false;
	/* Prefer /proc (Linux/OpenWrt) so the liveness probe cannot leak
	   "kill: No such process" noise into command output. */
	if (file_exists('/proc/self/stat')) return file_exists('/proc/' + pid);
	return run_capture('kill -0 ' + sprintf('%d', pid) + ' 2>/dev/null').ok;
}

function lock_is_stale(st) {
	if (st && st.type != 'directory') return true; /* leftover regular file from an older layout */
	let owner = read_lock_owner();
	let ts = owner.ts || (st && st.mtime) || 0;
	let age = time() - ts;
	if (age > LOCK_STALE_SECONDS) return true;
	if (owner.pid > 0 && !pid_alive(owner.pid)) return true;
	if (!owner.pid && age > 60) return true;
	return false;
}

function clear_stale_lock(inode) {
	let st = stat(PATH.lock);
	if (!st || (inode != null && st.inode != inode)) return false;
	if (st.type != 'directory') {
		try { unlink(PATH.lock); } catch (e) { return false; }
		return true;
	}
	try { unlink(PATH.lock + '/owner'); } catch (e) {}
	try { rmdir(PATH.lock); } catch (e) { return false; }
	return true;
}

function lock_acquire() {
	mkdir_p(PATH.run_dir);
	let pid = self_pid();
	let deadline = time() + LOCK_WAIT_SECONDS;
	while (true) {
		if (mkdir(PATH.lock) === true) {
			if (!write_text(PATH.lock + '/owner', sprintf('%d %d', pid, time()), 384)) {
				try { rmdir(PATH.lock); } catch (e) {}
				return { ok: false, lock: PATH.lock, error: '无法写入并发锁信息 ' + PATH.lock };
			}
			return { ok: true, lock: PATH.lock };
		}
		if (!file_exists(PATH.lock))
			return { ok: false, lock: PATH.lock, error: '无法创建并发锁 ' + PATH.lock + '，请检查 ' + PATH.run_dir + ' 的权限' };
		let st = stat(PATH.lock);
		if (st && lock_is_stale(st)) {
			if (clear_stale_lock(st.inode)) continue;
		}
		if (time() >= deadline) {
			let owner = read_lock_owner();
			return {
				ok: false, lock: PATH.lock,
				error: '另一个 singbox-lite 操作正在执行（锁 ' + PATH.lock + (owner.pid ? '，pid ' + owner.pid : '') + '），等待 ' + LOCK_WAIT_SECONDS + ' 秒后超时；如确认无进程占用可删除该目录后重试'
			};
		}
		sleep(1);
	}
}

function lock_release() {
	let owner = read_lock_owner();
	let pid = self_pid();
	if (pid > 0 && owner.pid > 0 && owner.pid != pid) return false;
	try { unlink(PATH.lock + '/owner'); } catch (e) {}
	try { rmdir(PATH.lock); } catch (e) { return false; }
	return true;
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
	let json = sprintf('%J', gen.config);
	let current = file_exists(PATH.config_json) ? read_text(PATH.config_json, '') : null;
	let changed = (current !== json);
	if (!changed) {
		/* Content is already deployed; skip the rewrite but still validate the
		   file we are about to leave running (core version/behaviour may have
		   changed since it was written). */
		let chk = check_config_with(core.path, PATH.config_json);
		if (!chk.ok) return { ok: false, changed: false, error: '配置校验失败', detail: chk.output };
		return { ok: true, changed: false, bytes: length(json), warnings: gen.warnings };
	}
	let tmp = PATH.config_json + '.tmp';
	if (!write_text(tmp, json, 384)) return { ok: false, changed: true, error: '写入临时配置失败' };
	let chk = check_config_with(core.path, tmp);
	if (!chk.ok) {
		try { unlink(tmp); } catch (e) {}
		return { ok: false, changed: true, error: '配置校验失败', detail: chk.output };
	}
	if (current != null) {
		let backup = run_capture('cp ' + sh_quote(PATH.config_json) + ' ' + sh_quote(PATH.config_bak));
		if (!backup.ok) {
			try { unlink(tmp); } catch (e) {}
			return { ok: false, changed: true, error: '备份旧配置失败' };
		}
	}
	if (rename(tmp, PATH.config_json) !== true) {
		try { unlink(tmp); } catch (e) {}
		return { ok: false, changed: true, error: '替换配置失败' };
	}
	return { ok: true, changed: true, bytes: length(json), warnings: gen.warnings };
}

function restore_config_backup() {
	if (!file_exists(PATH.config_bak)) return false;
	let tmp = PATH.config_json + '.rollback';
	let cp = run_capture('cp ' + sh_quote(PATH.config_bak) + ' ' + sh_quote(tmp));
	if (!cp.ok) {
		try { unlink(tmp); } catch (e) {}
		return false;
	}
	if (rename(tmp, PATH.config_json) !== true) {
		try { unlink(tmp); } catch (e) {}
		return false;
	}
	return true;
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

function truncate_detail(text, limit) {
	text = trim(text == null ? '' : sprintf('%s', text));
	let max = int(limit || POST_UPGRADE_DETAIL_LIMIT);
	if (max < 1) max = POST_UPGRADE_DETAIL_LIMIT;
	if (length(text) <= max) return text;
	/* 不要从 UTF-8 多字节字符中间截断，避免写出的 JSON 不是合法 UTF-8。 */
	let n = max;
	let b = ord(substr(text, n - 1, 1));
	if (b >= 0x80) {
		let i = n - 1;
		while (i >= 0 && (ord(substr(text, i, 1)) & 0xc0) == 0x80) i--;
		if (i >= 0) {
			b = ord(substr(text, i, 1));
			let need = b < 0xe0 ? 2 : (b < 0xf0 ? 3 : 4);
			if (i + need > n) n = i;
		}
	}
	return substr(text, 0, n);
}

function write_post_upgrade_status(obj) {
	let status = { updated: now_string() };
	for (let k in keys(obj || {})) status[k] = obj[k];
	if (status.detail != null) status.detail = truncate_detail(status.detail);
	/* postinst may call this before anything else created /tmp/singbox-lite. */
	mkdir_p(PATH.run_dir);
	write_json(PATH.post_upgrade_status, status, 384);
	return status;
}

function post_upgrade_fail(error, detail, extra) {
	let status = { state: 'error', ok: false, error: error };
	if (length(trim(detail == null ? '' : sprintf('%s', detail)))) status.detail = detail;
	for (let k in keys(extra || {})) status[k] = extra[k];
	status = write_post_upgrade_status(status);
	let message = '插件升级后自动重建配置失败：' + error;
	if (length(status.detail || '')) message += '；' + status.detail;
	log_app(truncate_detail(message));
	return status;
}

function restart_service() {
	let r = run_capture(sh_quote(PATH.init) + ' restart 2>&1');
	sleep(3);
	return { ok: r.ok && service_running(), rc: r.rc, out: trim(r.out == null ? '' : r.out) };
}

function core_log_tail(max_bytes) {
	let file = PATH.log_dir + '/core.log';
	if (!file_exists(file)) return '';
	let r = run_capture('tail -c ' + int(max_bytes || 4096) + ' ' + sh_quote(file) + ' 2>/dev/null');
	return trim(r.out == null ? '' : r.out);
}

/*
 * 插件包升级后基于当前 UCI/meta 重建 config.json：生成 → 校验 → 按
 * auto_apply 决定是否重启（失败回滚）。首装或缺少核心时只写 skipped，
 * 绝不在这里下载核心/面板/订阅；下载必须由用户在 LuCI 里手动触发。
 */
function cmd_post_upgrade(cfg, opts) {
	opts = opts || {};
	if (!file_exists(PATH.config_json))
		return write_post_upgrade_status({ state: 'skipped', ok: true, skipped: 'first-install' });
	let core = check_core(cfg);
	if (!core.ok)
		return write_post_upgrade_status({
			state: 'skipped', ok: true, skipped: 'no-core',
			hint: (core.error || '未找到可用的 sing-box 核心') + '；升级不会自动下载核心，请在 LuCI 中手动下载/更新'
		});
	ensure_panel_secret(cfg);
	let gen = generate(cfg);
	if (!gen.ok) {
		let errors = [];
		for (let e in gen.errors || []) push(errors, sprintf('%s', e));
		return post_upgrade_fail('配置生成失败', join('; ', errors));
	}
	let saved = save_config(cfg, gen);
	if (!saved.ok)
		return post_upgrade_fail(saved.error || '配置校验失败', saved.detail || '');

	let status = { state: 'done', ok: true, changed: saved.changed === true, restarted: false };
	if (!status.changed)
		return write_post_upgrade_status(status);

	let auto_apply = (cfg.main || {}).auto_apply != '0';
	if (opts['no-restart'] != true && auto_apply && service_running()) {
		let first = restart_service();
		if (first.ok) {
			status.restarted = true;
			return write_post_upgrade_status(status);
		}
		/* 新配置起不来：回到上一份经过校验的配置，再重启一次。 */
		let detail = '首次重启失败（rc=' + int(first.rc || 0) +
			(length(first.out) ? '，输出：' + truncate_detail(first.out, 500) : '') + '）';
		let rolled_back = false;
		if (restore_config_backup()) {
			let second = restart_service();
			detail += '；已回滚配置并再次重启' + (second.ok ? '成功' : '失败') +
				'（rc=' + int(second.rc || 0) +
				(length(second.out) ? '，输出：' + truncate_detail(second.out, 500) : '') + '）';
			rolled_back = second.ok;
		} else {
			detail += '；没有可回滚的配置备份';
		}
		let tail = truncate_detail(core_log_tail(4096), 500);
		if (length(tail)) detail += '；核心日志尾部：' + tail;
		return post_upgrade_fail(
			'自动重建配置后重启失败' + (rolled_back ? '，已回滚到上一份配置' : ''),
			detail, { changed: true, restarted: false, rolled_back: rolled_back }
		);
	}
	return write_post_upgrade_status(status);
}

/*
 * update-plugin 全程持有 CLI 锁。apk 安装完成后，本进程仍是升级前的旧代码，
 * 因此不能在同进程里重建 JSON（会继续用旧 generator）。这里先以 no_done
 * 完成安装/UCI 恢复，再释放锁，用新安装的 PATH.cli 子进程执行
 * `post-upgrade --json`（新代码自己拿锁重建、校验、按 auto_apply 重启），
 * 读回结果后重新拿锁并写 plugin-update.json 的 done。
 */
function cmd_update_plugin(cfg, opts) {
	let update_opts = {};
	for (let k in keys(opts || {})) update_opts[k] = opts[k];
	update_opts.no_done = true;
	let result = update_plugin(cfg, update_opts);
	if (!result.ok) return result;

	let post = null;
	let degraded = '';
	if (lock_release()) {
		/* New CLI: freshly installed code, handles the lock itself. */
		let run = run_capture(sh_quote(PATH.cli) + ' post-upgrade --json 2>&1');
		let out = trim(run.out == null ? '' : run.out);
		if (length(out)) {
			try {
				let parsed = json(out);
				if (type(parsed) == 'object' && parsed != null && parsed.state != null)
					post = parsed;
			} catch (e) {}
		}
		if (post == null) {
			let file_status = read_json(PATH.post_upgrade_status, null);
			if (type(file_status) == 'object' && file_status != null && file_status.state != null)
				post = file_status;
		}
		if (post == null) {
			post = {
				state: 'error', ok: false, error: '配置重建失败',
				detail: length(out) ? out : ('新 CLI 执行失败，退出码 ' + int(run.rc || 0))
			};
			try { post = write_post_upgrade_status(post); } catch (e) {}
		}
		/* main() releases the lock again on exit; take it back so that release
		   can only remove our own lock, never a concurrent operation's. */
		let relock = lock_acquire();
		if (!relock.ok) {
			degraded = '重新获取 CLI 锁失败：' + (relock.error || 'unknown');
			log_app('插件自更新重建后' + degraded);
		}
	} else {
		/* Should not happen; do not spawn the new CLI (it would hit our lock).
		   Fall back to the old in-process rebuild and report the degradation. */
		let fresh = cfg;
		try { fresh = load_config(); } catch (e) { fresh = cfg; }
		try {
			post = cmd_post_upgrade(fresh, {});
		} catch (e) {
			post = { state: 'error', ok: false, error: '配置重建异常', detail: sprintf('%s', e) };
			try { post = write_post_upgrade_status(post); } catch (e2) {}
		}
		degraded = '无法释放 CLI 锁，已回退到旧进程重建（未调用新 CLI）';
		log_app('插件自更新后' + degraded);
	}

	mkdir_p(PATH.run_dir);
	let status = {
		state: 'done', updated: now_string(),
		version: result.version, tag: result.tag, restored: result.restored,
		config: post
	};
	if (length(degraded)) status.degraded = degraded;
	write_json(PATH.plugin_update_status, status, 384);
	result.config = post;
	if (length(degraded)) result.degraded = degraded;
	return result;
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

function cmd_check(cfg) {
	ensure_panel_secret(cfg);
	let gen = generate(cfg);
	if (!gen.ok) return { ok: false, errors: gen.errors, warnings: gen.warnings };
	let saved = save_config(cfg, gen);
	if (!saved.ok)
		return { ok: false, error: saved.error || '配置校验失败', detail: saved.detail || '', errors: [ saved.error || '配置校验失败' ], warnings: gen.warnings };
	sync_cron(cfg);
	let core = core_status(cfg);
	return { ok: true, error: null, detail: '', changed: saved.changed === true, warnings: gen.warnings, core: core.version || '' };
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
			status.changed = saved.changed === true;
			status.restarted = false;
			sync_cron(cfg);
			let auto_apply = (cfg.main || {}).auto_apply != '0';
			if (saved.changed && service_running() && opts['no-restart'] != true && auto_apply) {
				let rc = system([PATH.init, 'restart']);
				sleep(3);
				status.restarted = (rc == 0 && service_running());
				if (!status.restarted) {
					/* keep the previous known-good config and bring the service
					   back up; only report failure when rollback fails too. */
					if (restore_config_backup()) {
						let rc2 = system([PATH.init, 'restart']);
						sleep(3);
						if (rc2 == 0 && service_running()) {
							status.rolled_back = true;
							push(status.warnings, '新配置重启失败，已回滚到上一份配置');
						} else {
							status.ok = false;
							status.rolled_back = false;
							status.errors = [ '新配置重启失败，回滚后仍无法启动' ];
						}
					} else {
						status.ok = false;
						status.rolled_back = false;
						status.errors = [ '新配置重启失败，且没有可回滚的配置备份' ];
					}
				}
			}
		}
	}
	mkdir_p(PATH.run_dir);
	write_json(PATH.refresh_status, status, 384);
	return status;
}

function tailscale_status(cfg) {
	let ts = cfg.tailscale || {};
	let enabled = ts.enabled == '1';
	let in_config = false, in_active = false;
	if (file_exists(PATH.config_json))
		in_config = match(read_text(PATH.config_json, ''), /"type":[ \t]*"tailscale"/) != null;
	let active = PATH.etc + '/active.json';
	if (file_exists(active))
		in_active = match(read_text(active, ''), /"type":[ \t]*"tailscale"/) != null;
	/*
	 * Without auth_key sing-box prints the interactive login URL and waits.
	 * Surface the last one from the core log so the LuCI page can link it
	 * instead of making the user dig through Logs.
	 */
	let auth_url = '';
	let log = PATH.log_dir + '/core.log';
	if (file_exists(log)) {
		let r = run_capture('tail -c 262144 ' + sh_quote(log) + ' 2>/dev/null');
		let rest = r.out || '';
		while (length(rest)) {
			let m = match(rest, /Waiting for authentication: (https?:\/\/[^ \t\r\n"']+)/);
			if (!m) break;
			auth_url = m[1];
			rest = substr(rest, index(rest, m[0]) + length(m[0]));
		}
	}
	return { enabled: enabled, in_config: in_config, in_active: in_active, auth_url: auth_url };
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
	for (let n in collected.nodes) push(node_list, { id: n.id, legacy_id: n.legacy_id, fingerprint: n.fingerprint, name: n.name, type: n.type, server: n.server, port: n.server_port, country: n.country, country_mode: n.country_mode || 'auto', native: n.native, native_mode: n.native_mode || 'auto', source: n.source_name });
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
		tailscale: tailscale_status(cfg),
		last_refresh: read_json(PATH.refresh_status, null)
	};
}

function cmd_update_rulesets(cfg, opts) {
	if (opts.id) return update_ruleset(cfg, opts.id);
	return update_builtin_rulesets((cfg.main && cfg.main.core_mirror) || '');
}

function cmd_log(opts) {
	let lines = int(opts.lines || 100);
	if (lines < 1) lines = 100;
	if (lines > 10000) lines = 10000;
	let out = '';
	for (let file in [ PATH.log_dir + '/core.log', PATH.log_dir + '/app.log' ]) {
		if (!file_exists(file)) continue;
		let r = run_capture('tail -n ' + lines + ' ' + sh_quote(file) + ' 2>/dev/null');
		if (!length(trim(r.out))) continue;
		out += '=== ' + file + ' ===\n' + r.out;
		if (substr(out, -1) != '\n') out += '\n';
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

function dispatch(argv) {
	let cmd = argv[0] || 'help';
	let opts = parse_args(slice(argv, 1));
	let cfg = null;
	try {
		if (cmd == 'version') return { ok: true, version: VERSION };
		if (cmd == 'help') return { ok: true, commands: [ 'preview', 'check', 'build', 'post-upgrade', 'refresh', 'status', 'update-rulesets', 'update-core', 'update-plugin', 'core-check', 'core-rollback', 'plugin-status', 'plugin-check', 'release-scan', 'panel-status', 'panel-proxies', 'panel-connections', 'panel-select', 'panel-delay', 'panel-close', 'panel-secret', 'dashboard-status', 'update-dashboard', 'parse-link', 'log' ] };
		if (cmd == 'parse-link') {
			let p = parse_link(opts._[0] || '');
			return p;
		}
		if (cmd == 'core-rollback') return rollback_core();
		if (cmd == 'plugin-status') return plugin_status();
		if (cmd == 'core-check') {
			try { cfg = load_config(); } catch (e) {}
			let l = latest_tag((cfg && cfg.main && cfg.main.core_mirror) || '');
			if (!l.ok) return l;
			let asset = arch_asset();
			if (!asset) return { ok: false, error: '当前架构没有可用资产' };
			let dl = download_url(l.tag, asset, (cfg && cfg.main && cfg.main.core_mirror) || '');
			return { ok: true, tag: l.tag, asset: asset, url: dl.url, version: dl.version };
		}
		cfg = load_config();
		if (cmd == 'plugin-check') return plugin_check(cfg);
		if (cmd == 'release-scan') return cmd_release_scan(cfg);
		if (cmd == 'update-plugin') return cmd_update_plugin(cfg, opts);
		if (cmd == 'panel-status') return panel_status(cfg);
		if (cmd == 'dashboard-status') return dashboard_status(cfg);
		if (cmd == 'update-dashboard') return update_dashboard(cfg, opts);
		if (cmd == 'panel-proxies') return panel_proxies(cfg);
		if (cmd == 'panel-connections') return panel_connections(cfg, int(opts.limit || 30));
		if (cmd == 'panel-select') return panel_select(cfg, opts.group || '', opts.node || '');
		if (cmd == 'panel-delay') return panel_delay(cfg, opts.group || '');
		if (cmd == 'panel-close') return panel_close(cfg, opts.id || '');
		if (cmd == 'panel-secret') {
			let secret = random_secret();
			if (getenv('SINGBOX_LITE_CONFIG_JSON') == null) {
				uci_set('panel', 'secret', secret);
				uci_commit();
			}
			return { ok: true, secret: secret };
		}
		if (cmd == 'preview') {
			let gen = generate(cfg);
			if (!gen.ok) return { ok: false, errors: gen.errors, warnings: gen.warnings };
			return { ok: true, config: gen.config, warnings: gen.warnings };
		}
		if (cmd == 'check') return cmd_check(cfg);
		if (cmd == 'build') return cmd_build(cfg, opts);
		if (cmd == 'post-upgrade') return cmd_post_upgrade(cfg, opts);
		if (cmd == 'refresh') return cmd_refresh(cfg, opts);
		if (cmd == 'status') return cmd_status(cfg);
		if (cmd == 'update-rulesets') return cmd_update_rulesets(cfg, opts);
		if (cmd == 'update-core') return update_core(cfg, opts);
		if (cmd == 'log') return cmd_log(opts);
		return { ok: false, error: 'unknown command: ' + cmd };
	} catch (e) {
		return { ok: false, error: 'exception: ' + e };
	}
}

const MUTATING_COMMANDS = {
	build: true, check: true, refresh: true, 'post-upgrade': true,
	'update-core': true, 'update-plugin': true, 'update-dashboard': true,
	'update-rulesets': true, 'core-rollback': true
};

function main() {
	let argv = ARGV;
	let cmd = argv[0] || 'help';
	let lock = null;
	if (MUTATING_COMMANDS[cmd]) {
		lock = lock_acquire();
		if (!lock.ok) return output(lock);
	}
	let result;
	try {
		result = dispatch(argv);
	} catch (e) {
		result = { ok: false, error: 'exception: ' + e };
	}
	if (lock) lock_release();
	return output(result);
}

main();
