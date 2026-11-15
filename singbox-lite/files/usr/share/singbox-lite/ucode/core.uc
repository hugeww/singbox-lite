'use strict';

import { trim, read_text, read_json, write_json, mkdir_p, file_exists, run_capture, log_app, PATH, human_size, now_string, sh_quote } from 'sbx_common';
import { unlink, rename, stat, chmod, dirname } from 'fs';
import { list_tags } from 'sbx_releases';

const MIN_VERSION = '1.14.4';
const CORE_REPO = 'SagerNet/sing-box';

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

function write_status(state, data) {
	let obj = { state: state, updated: now_string() };
	for (let k in keys(data || {})) obj[k] = data[k];
	mkdir_p(PATH.run_dir);
	write_json(PATH.core_update_status, obj, 384);
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
	if (file_exists(PATH.config_json)) {
		let check = system([new_bin, 'check', '-c', PATH.config_json]);
		if (check != 0) {
			write_status('error', { error: '新核心校验当前配置失败' });
			return { ok: false, error: '新核心校验当前配置失败' };
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
		write_status('error', { error: '写入核心失败' });
		return { ok: false, error: '写入核心失败' };
	}
	chmod(staged, 493);
	let staged_stat = stat(staged);
	if (!staged_stat || !staged_stat.size || !core_version(staged)) {
		try { unlink(staged); } catch (e) {}
		write_status('error', { error: '新核心写入后不可用' });
		return { ok: false, error: '新核心写入后不可用' };
	}
	let had_old = file_exists(PATH.core);
	if (had_old) {
		try { unlink(PATH.core_bak); } catch (e) {}
		if (rename(PATH.core, PATH.core_bak) !== true) {
			try { unlink(staged); } catch (e) {}
			write_status('error', { error: '备份旧核心失败' });
			return { ok: false, error: '备份旧核心失败' };
		}
	}
	if (rename(staged, PATH.core) !== true) {
		let restored = false;
		if (had_old && file_exists(PATH.core_bak) && !file_exists(PATH.core))
			restored = rename(PATH.core_bak, PATH.core) === true;
		try { unlink(staged); } catch (e) {}
		let msg = restored ? '替换核心失败，已恢复旧核心' : '替换核心失败';
		write_status('error', { error: msg });
		return { ok: false, error: msg };
	}
	system(['rm', '-rf', tmp_dir]);
	try { unlink(tmp_tar); } catch (e) {}
	if (service_running()) {
		write_status('restarting', { version: v });
		if (!restart_service()) {
			write_status('rolling-back', { version: v });
			let restored = false;
			if (file_exists(PATH.core_bak))
				restored = rename(PATH.core_bak, PATH.core) === true; /* atomic replace, no unlink window */
			let back_running = restored ? restart_service() : false;
			let msg = back_running ? '新核心启动失败，已回滚' : (restored ? '新核心启动失败，回滚后仍无法启动' : '新核心启动失败，且没有可回滚的核心');
			write_status('error', { error: msg });
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
	write_status('done', { version: v, asset: asset });
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

export { MIN_VERSION, CORE_REPO, version_parts, version_ge, core_path, core_version, core_status, latest_tag, core_tags, arch_asset, download_url, update_core, rollback_core };
