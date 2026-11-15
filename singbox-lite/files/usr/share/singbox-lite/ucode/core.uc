'use strict';

import { trim, read_text, read_json, write_text, write_json, mkdir_p, file_exists, run_capture, log_app, PATH, human_size, now_string, sh_quote } from 'sbx_common';
import { unlink, rename, stat, chmod, dirname, readfile, writefile } from 'fs';
import { list_tags } from 'sbx_releases';

const MIN_VERSION = '1.14.4';
const CORE_REPO = 'SagerNet/sing-box';
/* 单条日志/状态详情截断长度：既够定位问题，又不会把 UI 或 app.log 撑爆。 */
const UPDATE_DETAIL_LIMIT = 2000;

function version_parts(v) {
	let out = [];
	for (let p in split(trim(v || '0'), '.')) push(out, int(p));
	while (length(out) < 3) push(out, 0);
	return out;
}

function version_ge(a, b) {
	let ap = version_parts(a), bp = version_parts(b);
	for (let i = 0; i < 3; i++) {
		if (ap[i] > bp[i]) return true;
		if (ap[i] < bp[i]) return false;
	}
	return true;
}

/*
 * Migrate a parsed config for the target core version. Newer sing-box releases
 * drop fields that older configs still carry, and `sing-box check` rejects
 * them. Only fields listed here are deleted; nothing is ever added. The config
 * object is updated in place (the caller re-serializes it afterwards) and
 * `changes` holds one human readable description per edit, so the update can
 * log/report what was migrated. Version rules are appended below.
 */
function migrate_config_for_core(config, version) {
	let changes = [];
	if (type(config) != 'object') return { config: config, changes: changes };
	let v = trim(version == null ? '' : sprintf('%s', version));
	if (!length(v)) return { config: config, changes: changes };

	/* sing-box 1.16: cache_file rdrc options and the DNS rule action field were removed. */
	if (version_ge(v, '1.16.0')) {
		let exp = config.experimental;
		if (type(exp) == 'object') {
			let cache = exp.cache_file;
			if (type(cache) == 'object') {
				if (cache.rdrc_timeout != null) {
					delete cache.rdrc_timeout;
					push(changes, '移除 experimental.cache_file.rdrc_timeout（sing-box 1.16 已删除）');
				}
				if (cache.store_rdrc != null) {
					delete cache.store_rdrc;
					push(changes, '移除 experimental.cache_file.store_rdrc（sing-box 1.16 已删除）');
				}
			}
		}
		let dns = config.dns;
		if (type(dns) == 'object' && type(dns.rules) == 'array') {
			let n = 0;
			for (let rule in dns.rules) {
				if (type(rule) == 'object' && rule.strategy != null) {
					delete rule.strategy;
					n++;
				}
			}
			if (n > 0)
				push(changes, sprintf('移除 dns.rules 中 %d 条规则的 strategy（sing-box 1.16 已删除 DNS 规则动作）', n));
		}
	}

	/* sing-box 1.17: the TUN inbound stack field was removed. */
	if (version_ge(v, '1.17.0')) {
		let inbounds = config.inbounds;
		if (type(inbounds) == 'array') {
			let n = 0;
			for (let inbound in inbounds) {
				if (type(inbound) == 'object' && inbound.stack != null) {
					delete inbound.stack;
					n++;
				}
			}
			if (n > 0)
				push(changes, sprintf('移除 %d 个入站的 stack 字段（sing-box 1.17 已删除 TUN stack）', n));
		}
	}

	/* 后续版本：在下面继续追加 `if (version_ge(v, 'x.y.z')) { ... }` 规则。 */
	return { config: config, changes: changes };
}

function core_path(cfg) {
	if (cfg && cfg.main && cfg.main.core_source == 'system') return PATH.system_core;
	return PATH.core;
}

function core_version(path) {
	path = path || PATH.core;
	if (!file_exists(path)) return null;
	let r = run_capture(path + ' version 2>/dev/null');
	if (!r.ok) return null;
	let m = match(r.out, /sing-box version ([0-9]+\.[0-9]+\.[0-9]+)/);
	return m ? m[1] : null;
}

function core_status(cfg) {
	let path = core_path(cfg);
	let version = core_version(path);
	let managed = file_exists(PATH.core);
	let system = file_exists(PATH.system_core);
	let meta = read_json(PATH.core_meta, {});
	return {
		ok: true,
		path: path,
		version: version,
		managed: managed,
		system: system,
		source: (cfg && cfg.main && cfg.main.core_source) || 'managed',
		minimum: MIN_VERSION,
		meets_minimum: version ? version_ge(version, MIN_VERSION) : false,
		meta: meta
	};
}

function latest_tag(mirror) {
	let l = list_tags(CORE_REPO, mirror || '', 5);
	if (l.ok && length(l.tags)) return { ok: true, tag: l.tags[0] };
	let r = run_capture("curl -sIL --connect-timeout 10 --max-time 30 -o /dev/null -w '%{url_effective}' 'https://github.com/SagerNet/sing-box/releases/latest'");
	if (!r.ok) return { ok: false, error: '无法访问 GitHub releases' };
	let url = trim(r.out);
	let pos = rindex(url, '/tag/');
	if (pos == null || pos < 0) return { ok: false, error: '无法解析最新版本' };
	return { ok: true, tag: substr(url, pos + 5), url: url };
}

function core_tags(cfg, limit) {
	let mirror = (cfg && cfg.main && cfg.main.core_mirror) || '';
	return list_tags(CORE_REPO, mirror, limit || 10);
}

function arch_asset(arch) {
	arch = arch || getenv('SINGBOX_LITE_ARCH') || '';
	if (!length(arch)) {
		let rel = read_text('/etc/openwrt_release', '');
		let m = match(rel, /DISTRIB_ARCH=['"]([^'"]+)['"]/);
		if (m) arch = m[1];
	}
	if (!length(arch)) {
		let u = run_capture('uname -m 2>/dev/null');
		arch = trim(u.out);
	}
	arch = lc(arch);
	if (arch == 'x86_64' || arch == 'amd64') return 'amd64-musl';
	if (match(arch, /^(i386|i486|i586|i686)/)) return '386-musl';
	if (match(arch, /^aarch64/)) return 'arm64-musl';
	if (match(arch, /^arm_cortex-a(5|7|8|9|1[0-9])/)) return 'armv7-musl';
	if (match(arch, /^arm_arm1176|^arm_arm1136/)) return 'armv6';
	if (match(arch, /^arm_arm926|^arm_xscale/)) return 'armv5';
	if (match(arch, /^mips64el/)) return 'mips64le-softfloat';
	if (match(arch, /^mips64/)) return 'mips64-softfloat';
	if (match(arch, /^mipsel/)) return 'mipsle-softfloat-musl';
	if (match(arch, /^mips/)) return 'mips-softfloat';
	if (match(arch, /^riscv64/)) return 'riscv64-musl';
	if (match(arch, /^loongarch64/)) return 'loong64-musl';
	return null;
}

function mirror_url(url, mirror) {
	if (!length(mirror || '')) return url;
	let prefix = substr(mirror, -1) == '/' ? mirror : mirror + '/';
	return prefix + url;
}

function download_url(tag, asset, mirror) {
	if (substr(tag, 0, 1) == 'v') tag = substr(tag, 1);
	let file = 'sing-box-' + tag + '-linux-' + asset + '.tar.gz';
	let url = 'https://github.com/SagerNet/sing-box/releases/download/v' + tag + '/' + file;
	return { url: mirror_url(url, mirror), file: file, version: tag };
}

function service_running() {
	if (!file_exists('/var/run/singbox-lite.pid')) return false;
	let pid = trim(read_text('/var/run/singbox-lite.pid', ''));
	if (!length(pid)) return false;
	return system(['kill', '-0', pid]) == 0;
}

function restart_service() {
	let rc = system([PATH.init, 'restart']);
	sleep(3);
	return rc == 0 && service_running();
}

/* 与 restart_service() 语义相同，但保留 init 的输出，供更新失败时写日志/状态。 */
function restart_service_capture() {
	let r = run_capture(sh_quote(PATH.init) + ' restart 2>&1');
	sleep(3);
	return { ok: r.ok && service_running(), out: r.out == null ? '' : r.out, rc: r.rc };
}

function write_status(state, data) {
	let obj = { state: state, updated: now_string() };
	for (let k in keys(data || {})) obj[k] = data[k];
	mkdir_p(PATH.run_dir);
	write_json(PATH.core_update_status, obj, 384);
}

/* 保留末尾 `limit` 字符（日志尾部信息量最大），并跳过被切开的 UTF-8 续字节。 */
function truncate_text(text, limit) {
	text = text == null ? '' : sprintf('%s', text);
	limit = int(limit || UPDATE_DETAIL_LIMIT);
	if (limit <= 0 || length(text) <= limit) return text;
	let start = length(text) - limit;
	while (start < length(text) && (ord(substr(text, start, 1)) & 0xc0) == 0x80) start++;
	return '…' + substr(text, start);
}

/* 读取文本文件尾部（用 tail -c 限制读入量，避免把整份 core.log 读进内存）。 */
function tail_text(path, max_bytes) {
	max_bytes = int(max_bytes || 8192);
	if (!length(path) || !file_exists(path)) return '';
	let r = run_capture('tail -c ' + max_bytes + ' ' + sh_quote(path) + ' 2>/dev/null');
	if (r.ok) return r.out == null ? '' : r.out;
	return read_text(path, '');
}

/*
 * 关键更新事件写入 app.log。common.uc 的 log_app() 引用了同模块里更晚定义的
 * now_string()（ucode 不会提升顶层函数），直接调用会抛错；这里仍然优先用
 * log_app，异常时按同样的格式自行追加，保证更新失败日志不会丢失。
 */
function log_update(message) {
	message = truncate_text(message);
	try { log_app(message); return; } catch (e) {}
	try {
		mkdir_p(PATH.log_dir);
		let file = PATH.log_dir + '/app.log';
		let old = readfile(file);
		if (old == null) old = '';
		if (length(old) > 1024 * 1024)
			old = substr(old, length(old) - 512 * 1024);
		writefile(file, old + sprintf('%s %s\n', now_string(), message));
	} catch (e) {}
}

function write_binary(dst, src) {
	let r = run_capture('cp ' + sh_quote(src) + ' ' + sh_quote(dst) + ' && chmod 755 ' + sh_quote(dst));
	return r.ok;
}

function update_core(cfg, opts) {
	opts = opts || {};
	let mirror = opts.mirror != null ? opts.mirror : ((cfg.main && cfg.main.core_mirror) || '');
	let tag = opts.version || (cfg.version && cfg.version.core_tag) || (cfg.main && cfg.main.core_version) || '';
	if (!length(tag)) {
		write_status('checking', { message: '查询最新版本' });
		let latest = latest_tag(mirror);
		if (!latest.ok) { write_status('error', { error: latest.error }); return { ok: false, error: latest.error }; }
		tag = latest.tag;
	}
	let asset = opts.asset || arch_asset();
	if (!length(asset || '')) {
		let err = '当前架构没有可用的 sing-box 资产，请设置 core_asset 或使用自定义 URL';
		write_status('error', { error: err });
		return { ok: false, error: err };
	}
	let dl = download_url(tag, asset, mirror);
	write_status('downloading', { message: '下载 ' + dl.url, url: dl.url });
	mkdir_p(PATH.run_dir);
	let tmp_tar = PATH.run_dir + '/sing-box.tar.gz';
	let tmp_dir = PATH.run_dir + '/core-extract';
	system(['rm', '-rf', tmp_dir]);
	mkdir_p(tmp_dir);
	let r = run_capture('curl -fsSL --connect-timeout 15 --max-time 300 -o ' + sh_quote(tmp_tar) + ' ' + sh_quote(dl.url));
	if (!r.ok) {
		write_status('error', { error: '下载失败' });
		return { ok: false, error: '下载失败，请检查网络或镜像' };
	}
	let st = stat(tmp_tar);
	if (!st || !st.size) {
		write_status('error', { error: '下载文件为空' });
		return { ok: false, error: '下载文件为空' };
	}
	let extract = system(['tar', '-xzf', tmp_tar, '-C', tmp_dir]);
	if (extract != 0) {
		write_status('error', { error: '解包失败' });
		return { ok: false, error: '解包失败' };
	}
	let version = substr(tag, 0, 1) == 'v' ? substr(tag, 1) : tag;
	let new_bin = tmp_dir + '/sing-box-' + version + '-linux-' + asset + '/sing-box';
	if (!file_exists(new_bin)) {
		let listing = run_capture('find ' + sh_quote(tmp_dir) + ' -name sing-box -type f 2>/dev/null');
		new_bin = trim(split_lines(listing.out)[0] || '');
	}
	if (!length(new_bin) || !file_exists(new_bin)) {
		write_status('error', { error: '未找到 sing-box 二进制' });
		return { ok: false, error: '未找到 sing-box 二进制' };
	}
	chmod(new_bin, 493); /* 0755 */
	let v = core_version(new_bin);
	if (!v) {
		write_status('error', { error: '新核心不可执行' });
		return { ok: false, error: '新核心不可执行' };
	}
	if (!version_ge(v, MIN_VERSION)) {
		write_status('error', { error: '版本低于最低要求 ' + MIN_VERSION });
		return { ok: false, error: '版本低于最低要求 ' + MIN_VERSION };
	}
	/* The live config is read once. A migrated candidate is validated with the
	   new binary BEFORE the live config is touched; the original text is kept
	   for a backup in case the migration is applied later. */
	let had_config = file_exists(PATH.config_json);
	let cfg_raw = null;
	let cfg_migrated = null;
	let cfg_changes = [];
	let cfg_candidate = PATH.run_dir + '/config.core-new.json';
	let cfg_backup = PATH.config_json + '.core-update.bak';
	let cfg_applied = false;
	if (had_config) {
		cfg_raw = read_text(PATH.config_json, null);
		if (cfg_raw == null) {
			let msg = '无法读取现有配置，未更新核心';
			let detail = truncate_text('无法读取 ' + PATH.config_json);
			log_update('核心更新到 ' + v + ' 中止：' + msg + '（' + detail + '）');
			write_status('error', { error: msg, detail: detail });
			return { ok: false, error: msg };
		}
		let cfg_obj = null;
		let parse_error = '';
		try { cfg_obj = json(cfg_raw); } catch (e) { parse_error = trim(sprintf('%s', e)); }
		if (cfg_obj == null) {
			let msg = '现有配置不是合法 JSON，未更新核心';
			let detail = truncate_text('目标版本 ' + v + '：' + (length(parse_error) ? parse_error : '解析结果为空'));
			log_update('核心更新到 ' + v + ' 中止：' + msg + '（' + detail + '）');
			write_status('error', { error: msg, detail: detail });
			return { ok: false, error: msg };
		}
		let mig = migrate_config_for_core(cfg_obj, v);
		cfg_migrated = mig.config;
		cfg_changes = mig.changes == null ? [] : mig.changes;
		if (length(cfg_changes))
			log_update('核心更新到 ' + v + '：需要迁移配置 — ' + join('；', cfg_changes));
		if (!write_text(cfg_candidate, sprintf('%J', cfg_migrated), 384)) {
			let msg = '写入候选配置失败，未更新核心';
			log_update('核心更新到 ' + v + ' 中止：' + msg);
			write_status('error', { error: msg, detail: '无法写入 ' + cfg_candidate });
			return { ok: false, error: msg };
		}
		let check = run_capture(sh_quote(new_bin) + ' check -c ' + sh_quote(cfg_candidate) + ' 2>&1');
		if (!check.ok) {
			let out = truncate_text(check.out == null ? '' : check.out, UPDATE_DETAIL_LIMIT - 160);
			let detail = '目标版本 ' + v + '，sing-box check 退出码 ' + int(check.rc) + (length(trim(out)) ? '：\n' + out : '');
			detail = truncate_text(detail);
			try { unlink(cfg_candidate); } catch (e) {}
			log_update('核心更新到 ' + v + ' 中止：新核心校验迁移后的配置失败\n' + truncate_text(detail, UPDATE_DETAIL_LIMIT - 120));
			write_status('error', { error: '新核心校验迁移后的配置失败', detail: detail });
			return { ok: false, error: '新核心校验迁移后的配置失败' };
		}
	}
	mkdir_p(dirname(PATH.core));
	let core_meta_bak = PATH.core_meta + '.bak';
	let old_meta = read_json(PATH.core_meta, null);
	write_status('installing', { message: '安装 ' + v });
	/* Stage next to the live core and validate the staged copy before the old
	   binary is moved away. A failed copy must never leave the system without
	   an executable core. */
	let staged = PATH.core + '.new';
	try { unlink(staged); } catch (e) {}
	if (!write_binary(staged, new_bin)) {
		try { unlink(staged); } catch (e) {}
		try { unlink(cfg_candidate); } catch (e) {}
		write_status('error', { error: '写入核心失败' });
		return { ok: false, error: '写入核心失败' };
	}
	chmod(staged, 493);
	let staged_stat = stat(staged);
	if (!staged_stat || !staged_stat.size || !core_version(staged)) {
		try { unlink(staged); } catch (e) {}
		try { unlink(cfg_candidate); } catch (e) {}
		write_status('error', { error: '新核心写入后不可用' });
		return { ok: false, error: '新核心写入后不可用' };
	}
	let had_old = file_exists(PATH.core);
	if (had_old) {
		try { unlink(PATH.core_bak); } catch (e) {}
		if (rename(PATH.core, PATH.core_bak) !== true) {
			try { unlink(staged); } catch (e) {}
			try { unlink(cfg_candidate); } catch (e) {}
			write_status('error', { error: '备份旧核心失败' });
			return { ok: false, error: '备份旧核心失败' };
		}
	}
	if (rename(staged, PATH.core) !== true) {
		let restored = false;
		if (had_old && file_exists(PATH.core_bak) && !file_exists(PATH.core))
			restored = rename(PATH.core_bak, PATH.core) === true;
		try { unlink(staged); } catch (e) {}
		try { unlink(cfg_candidate); } catch (e) {}
		let msg = restored ? '替换核心失败，已恢复旧核心' : '替换核心失败';
		write_status('error', { error: msg });
		return { ok: false, error: msg };
	}
	system(['rm', '-rf', tmp_dir]);
	try { unlink(tmp_tar); } catch (e) {}
	/* The new core is in place: apply the migrated config before restarting so a
	   bad write never leaves a half-updated pair. The original text is backed up
	   next to the config, and the migrated JSON is staged and renamed, so
	   config.json is never truncated in place. */
	if (had_config && length(cfg_changes)) {
		let write_error = '';
		let write_detail = '';
		if (!write_text(cfg_backup, cfg_raw, 384)) {
			write_error = '备份现有配置失败';
			write_detail = '无法写入 ' + cfg_backup;
		} else {
			let cfg_new = PATH.config_json + '.new';
			let written = write_text(cfg_new, sprintf('%J', cfg_migrated), 384);
			if (!written || rename(cfg_new, PATH.config_json) !== true) {
				try { unlink(cfg_new); } catch (e) {}
				try { unlink(cfg_backup); } catch (e) {}
				write_error = '写入迁移后的配置失败';
				write_detail = '无法写入 ' + PATH.config_json;
			} else {
				cfg_applied = true;
			}
		}
		if (length(write_error)) {
			let core_note = '';
			if (had_old) {
				if (file_exists(PATH.core_bak) && rename(PATH.core_bak, PATH.core) === true)
					core_note = '，已恢复旧核心';
				else
					core_note = '，恢复旧核心失败';
			} else {
				try { unlink(PATH.core); } catch (e) {}
				core_note = '，已移除新核心';
			}
			let msg = write_error + core_note;
			let detail = truncate_text(write_detail + '；目标版本 ' + v + core_note);
			try { unlink(cfg_candidate); } catch (e) {}
			log_update('核心更新到 ' + v + ' 中止：' + msg + '（' + detail + '）');
			write_status('error', { error: msg, detail: detail });
			return { ok: false, error: msg };
		}
	}
	if (service_running()) {
		write_status('restarting', { version: v });
		let first = restart_service_capture();
		if (!first.ok) {
			write_status('rolling-back', { version: v });
			/* Bring back the old pair: the previous core needs the pre-migration
			   JSON, otherwise it would keep failing on the very fields the new
			   version cannot parse (and the verbose reason lives in core.log). */
			let cfg_restored = true;
			if (cfg_applied) {
				cfg_restored = file_exists(cfg_backup) && rename(cfg_backup, PATH.config_json) === true;
			}
			let restored = false;
			if (file_exists(PATH.core_bak))
				restored = rename(PATH.core_bak, PATH.core) === true; /* atomic replace, no unlink window */
			let back = restored ? restart_service_capture() : { ok: false, out: '', rc: -1 };
			let msg;
			if (!restored) msg = '新核心启动失败，且没有可回滚的核心';
			else if (!back.ok) msg = '新核心启动失败，回滚后仍无法启动';
			else if (cfg_applied && !cfg_restored) msg = '新核心启动失败，已回滚核心但配置恢复失败';
			else msg = '新核心启动失败，已回滚';
			let first_out = truncate_text(first.out, 700);
			let back_out = truncate_text(back.out, 400);
			let log_tail = truncate_text(tail_text(PATH.log_dir + '/core.log'), 700);
			let parts = [ '目标版本 ' + v ];
			push(parts, '首次 restart 退出码 ' + int(first.rc) + (length(trim(first_out)) ? '：' + first_out : ''));
			if (cfg_applied) push(parts, '恢复配置：' + (cfg_restored ? '成功' : '失败'));
			if (restored) push(parts, '回滚后 restart：' + (back.ok ? '成功' : '失败') + (length(trim(back_out)) ? '：' + back_out : ''));
			else push(parts, '未找到可回滚的核心');
			if (length(trim(log_tail))) push(parts, 'core.log 尾部：' + log_tail);
			let detail = truncate_text(join('\n', parts));
			try { unlink(cfg_candidate); } catch (e) {}
			log_update('核心更新到 ' + v + ' 失败：' + msg + '\n' + truncate_text(detail, UPDATE_DETAIL_LIMIT - 200));
			write_status('error', { error: msg, detail: detail });
			return { ok: false, error: msg };
		}
	}
	/* Write metadata only after the new core is actually in place and (when
	   running) the service came back. Keep the previous metadata next to the
	   .bak core so a later manual rollback restores a consistent version. */
	if (old_meta != null)
		write_json(core_meta_bak, old_meta, 384);
	else {
		try { unlink(core_meta_bak); } catch (e) {}
	}
	write_json(PATH.core_meta, {
		version: v, asset: asset, tag: tag, source: dl.url,
		installed_at: now_string(), size: st.size
	}, 384);
	try { unlink(cfg_candidate); } catch (e) {}
	if (cfg_applied) {
		try { unlink(cfg_backup); } catch (e) {}
	}
	write_status('done', { version: v, asset: asset, migrated: cfg_changes });
	return { ok: true, version: v, asset: asset };
}

function rollback_core() {
	if (!file_exists(PATH.core_bak)) return { ok: false, error: '没有可回滚的核心' };
	/* Validate the backup before consuming it, then replace the current core
	   with a single atomic rename (no delete-then-rename window). */
	let v = core_version(PATH.core_bak);
	if (!v) return { ok: false, error: '备份的核心不可执行，未回滚' };
	if (rename(PATH.core_bak, PATH.core) !== true) return { ok: false, error: '回滚失败' };
	let meta_bak = PATH.core_meta + '.bak';
	if (file_exists(meta_bak)) {
		try { rename(meta_bak, PATH.core_meta); } catch (e) {}
	} else {
		write_json(PATH.core_meta, { version: v, source: 'core-rollback', installed_at: now_string() }, 384);
	}
	if (service_running() && !restart_service())
		return { ok: false, error: '核心已回滚，但服务重启失败', version: v };
	return { ok: true, version: v };
}

export { MIN_VERSION, CORE_REPO, version_parts, version_ge, migrate_config_for_core, core_path, core_version, core_status, latest_tag, core_tags, arch_asset, download_url, update_core, rollback_core };
