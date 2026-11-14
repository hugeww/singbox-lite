'use strict';

import { trim, read_text, write_text, write_json, mkdir_p, run_capture, sh_quote, PATH, VERSION, now_string } from 'sbx_common';
import { unlink, stat } from 'fs';
import { list_tags, latest_tag, mirror_url } from 'sbx_releases';

const PLUGIN_REPO = 'hugeww/singbox-lite';
const PLUGIN_PACKAGE = 'luci-app-singbox-lite';
const PLUGIN_BRANCH = 'openwrt-25.12';
const PLUGIN_ARCHS = [ 'x86_64', 'aarch64_cortex-a53' ];

/* Package version without the "v" prefix and the OpenWrt release suffix. */
function base_version(v) {
	v = trim(v == null ? '' : v);
	if (substr(v, 0, 1) == 'v') v = substr(v, 1);
	let dash = index(v, '-');
	if (dash >= 0) v = substr(v, 0, dash);
	return v;
}

/* DISTRIB_ARCH from the release file, falling back to uname. */
function distrib_arch() {
	let rel = read_text('/etc/openwrt_release', '');
	let m = match(rel, /DISTRIB_ARCH=['"]([^'"]+)['"]/);
	if (m) return m[1];
	let u = run_capture('uname -m 2>/dev/null');
	let arch = trim(u.out);
	if (arch == 'x86_64' || arch == 'amd64') return 'x86_64';
	if (arch == 'aarch64' || arch == 'arm64') return 'aarch64_cortex-a53';
	return arch;
}

/* "luci-app-singbox-lite-0.1.0-r1 x86_64 {...}" (apk list --installed) */
function parse_apk_list(text, name) {
	for (let line in split(text == null ? '' : text, '\n')) {
		line = trim(line);
		if (index(line, name + '-') != 0) continue;
		let rest = substr(line, length(name) + 1);
		let sp = index(rest, ' ');
		if (sp >= 0) rest = substr(rest, 0, sp);
		if (length(rest)) return rest;
	}
	return null;
}

/* /lib/apk/db/installed block format: P:<name> ... V:<version> */
function parse_apk_db(text, name) {
	let hit = false;
	for (let line in split(text == null ? '' : text, '\n')) {
		if (substr(line, 0, 2) == 'P:') {
			hit = trim(substr(line, 2)) == name;
			continue;
		}
		if (hit && substr(line, 0, 2) == 'V:') return trim(substr(line, 2));
	}
	return null;
}

/* opkg status output: "Package: <name>" / "Version: <version>" */
function parse_opkg_status(text, name) {
	let hit = false;
	for (let line in split(text == null ? '' : text, '\n')) {
		line = trim(line);
		if (substr(line, 0, 8) == 'Package:') {
			hit = trim(substr(line, 8)) == name;
			continue;
		}
		if (hit && substr(line, 0, 8) == 'Version:') return trim(substr(line, 8));
	}
	return null;
}

function installed_version() {
	let r = run_capture('apk list -I ' + sh_quote(PLUGIN_PACKAGE) + ' 2>/dev/null');
	if (r.ok) {
		let v = parse_apk_list(r.out, PLUGIN_PACKAGE);
		if (v) return v;
	}
	let v = parse_apk_db(read_text('/lib/apk/db/installed', ''), PLUGIN_PACKAGE);
	if (v) return v;
	r = run_capture('opkg status ' + sh_quote(PLUGIN_PACKAGE) + ' 2>/dev/null');
	if (r.ok) {
		v = parse_opkg_status(r.out, PLUGIN_PACKAGE);
		if (v) return v;
	}
	return null;
}

function plugin_status() {
	let installed = installed_version();
	return {
		ok: true,
		package: PLUGIN_PACKAGE,
		repo: PLUGIN_REPO,
		branch: PLUGIN_BRANCH,
		arch: distrib_arch(),
		archs: PLUGIN_ARCHS,
		version: installed || VERSION,
		installed: installed != null,
		code_version: VERSION
	};
}

function asset_name(arch) {
	return 'singbox-lite-' + arch + '-' + PLUGIN_BRANCH + '.tar.gz';
}

function download_url(tag, arch, mirror) {
	let t = substr(tag, 0, 1) == 'v' ? tag : 'v' + tag;
	let url = 'https://github.com/' + PLUGIN_REPO + '/releases/download/' + t + '/' + asset_name(arch);
	return { url: mirror_url(url, mirror), file: asset_name(arch), tag: t };
}

function write_status(state, data) {
	let obj = { state: state, updated: now_string() };
	for (let k in keys(data || {})) obj[k] = data[k];
	mkdir_p(PATH.run_dir);
	write_json(PATH.plugin_update_status, obj, 384);
}

function plugin_check(cfg) {
	let mirror = (cfg && cfg.main && cfg.main.core_mirror) || '';
	let current = installed_version();
	let l = list_tags(PLUGIN_REPO, mirror, 10);
	if (!l.ok) return { ok: false, error: l.error, current: current, tags: [] };
	let latest = l.tags[0];
	return {
		ok: true,
		current: current,
		latest: latest,
		tags: l.tags,
		arch: distrib_arch(),
		update_available: current != null && base_version(current) != base_version(latest)
	};
}

function collect_packages(dir) {
	let files = [];
	let listing = run_capture('find ' + sh_quote(dir) + ' -type f \\( -name "*.apk" -o -name "*.ipk" \\) 2>/dev/null');
	for (let line in split(listing.out, '\n')) {
		line = trim(line);
		if (length(line)) push(files, line);
	}
	return files;
}

function install_packages(files) {
	let apk_files = [], ipk_files = [];
	for (let f in files) {
		if (substr(f, -4) == '.ipk') push(ipk_files, f);
		else push(apk_files, f);
	}
	let last = { ok: false, out: '' };
	if (length(apk_files)) {
		let attempts = [
			'apk add --allow-untrusted',
			'apk add --allow-untrusted --force-overwrite',
			'apk add --allow-untrusted --force-reinstall'
		];
		for (let base in attempts) {
			let cmd = base;
			for (let f in apk_files) cmd += ' ' + sh_quote(f);
			last = run_capture(cmd + ' 2>&1');
			if (last.ok) return { ok: true, output: trim(last.out) };
		}
	}
	if (length(ipk_files)) {
		let cmd = 'opkg install --force-reinstall --force-overwrite';
		for (let f in ipk_files) cmd += ' ' + sh_quote(f);
		let r = run_capture(cmd + ' 2>&1');
		if (r.ok) return { ok: true, output: trim(r.out) };
		last = r;
	}
	return { ok: false, output: trim(last.out) };
}

function update_plugin(cfg, opts) {
	opts = opts || {};
	let mirror = opts.mirror != null ? opts.mirror : ((cfg && cfg.main && cfg.main.core_mirror) || '');
	let tag = opts.version || (cfg && cfg.version && cfg.version.plugin_tag) || '';
	if (!length(tag)) {
		write_status('checking', { message: '查询最新插件版本' });
		let l = latest_tag(PLUGIN_REPO, mirror, 5);
		if (!l.ok) {
			write_status('error', { error: l.error });
			return { ok: false, error: l.error };
		}
		tag = l.tag;
	}
	let arch = opts.arch || distrib_arch();
	if (index(PLUGIN_ARCHS, arch) < 0) {
		let err = '当前架构 ' + (arch || '未知') + ' 没有发布包（仅提供 ' + join('、', PLUGIN_ARCHS) + '）';
		write_status('error', { error: err });
		return { ok: false, error: err };
	}
	let dl = download_url(tag, arch, mirror);
	write_status('downloading', { message: '下载 ' + dl.url, url: dl.url, tag: tag });
	mkdir_p(PATH.run_dir);
	let tmp_tar = PATH.run_dir + '/plugin.tar.gz';
	let tmp_dir = PATH.run_dir + '/plugin-extract';
	system([ 'rm', '-rf', tmp_dir ]);
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
	if (system([ 'tar', '-xzf', tmp_tar, '-C', tmp_dir ]) != 0) {
		write_status('error', { error: '解包失败' });
		return { ok: false, error: '解包失败' };
	}
	let files = collect_packages(tmp_dir);
	if (!length(files)) {
		write_status('error', { error: '发布包内没有安装包文件' });
		return { ok: false, error: '发布包内没有安装包文件' };
	}
	write_status('installing', { tag: tag, files: length(files) });
	mkdir_p(PATH.run_dir);
	let cfg_snapshot = read_text(PATH.config, '');
	if (length(cfg_snapshot)) write_text(PATH.run_dir + '/config.uci.bak', cfg_snapshot, 384);
	let inst = install_packages(files);
	if (!inst.ok) {
		write_status('error', { error: '安装失败', detail: substr(inst.output || '', 0, 400) });
		return { ok: false, error: '安装失败', detail: inst.output };
	}
	let restored = false;
	if (length(cfg_snapshot) && read_text(PATH.config, '') != cfg_snapshot) {
		/* The upgrade replaced the UCI config; put the user's settings back. */
		if (write_text(PATH.config, cfg_snapshot, 384)) {
			system([ 'uci', '-q', 'commit', 'singbox-lite' ]);
			restored = true;
		}
	}
	system([ 'rm', '-rf', tmp_dir ]);
	try { unlink(tmp_tar); } catch (e) {}
	let version = installed_version();
	write_status('done', { version: version, tag: dl.tag, restored: restored });
	return { ok: true, version: version, tag: dl.tag, package: PLUGIN_PACKAGE, restored: restored, detail: inst.output };
}

export {
	PLUGIN_REPO, PLUGIN_PACKAGE, PLUGIN_BRANCH, PLUGIN_ARCHS,
	base_version, distrib_arch, parse_apk_list, parse_apk_db, parse_opkg_status,
	installed_version, plugin_status, asset_name, download_url, plugin_check, update_plugin
};