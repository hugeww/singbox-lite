'use strict';

import { trim, run_capture, sh_quote, write_json, mkdir_p, file_exists, PATH, now_string } from 'sbx_common';
import { unlink, rename, stat } from 'fs';
import { mirror_url } from 'sbx_releases';

const DEFAULT_PORT = 9090;
const DEFAULT_LISTEN = '127.0.0.1';
const DEFAULT_DELAY_URL = 'https://www.gstatic.com/generate_204';
const MAX_DELAY_MEMBERS = 12;
const DASHBOARD_REPO = 'SagerNet/sing-box-dashboard';
const DASHBOARD_ARCHIVE = 'https://github.com/' + DASHBOARD_REPO + '/archive/refs/heads/gh-pages.zip';

function panel_config(cfg) {
	let p = (cfg && cfg.panel) || {};
	let listen = trim(p.listen || DEFAULT_LISTEN);
	if (!length(listen)) listen = DEFAULT_LISTEN;
	let port = int(p.port || DEFAULT_PORT);
	if (port < 1 || port > 65535) port = DEFAULT_PORT;
	return {
		enabled: p.enabled == '1',
		listen: listen,
		port: port,
		secret: trim(p.secret || '')
	};
}

function delay_url(cfg, p) {
	let url = (cfg && cfg.egress && cfg.egress.auto_url) || '';
	return length(trim(url)) ? trim(url) : ((p && p.url) || DEFAULT_DELAY_URL);
}

/* Official sing-box dashboard (SagerNet/sing-box-dashboard), served by sing-box via external_ui. */
function dashboard_dir() {
	return PATH.etc + '/ui';
}

function dashboard_installed() {
	return file_exists(dashboard_dir() + '/index.html');
}

function dashboard_archive_url(mirror) {
	return mirror_url(DASHBOARD_ARCHIVE, mirror);
}

function dashboard_selected(cfg) {
	return ((cfg && cfg.panel && cfg.panel.dashboard) || 'native');
}

function dashboard_status(cfg) {
	let p = panel_config(cfg);
	return {
		ok: true,
		repo: DASHBOARD_REPO,
		selected: dashboard_selected(cfg),
		installed: dashboard_installed(),
		path: dashboard_dir(),
		port: p.port,
		url_path: '/ui/'
	};
}

function write_dashboard_status(state, data) {
	let obj = { state: state, updated: now_string() };
	for (let k in keys(data || {})) obj[k] = data[k];
	mkdir_p(PATH.run_dir);
	write_json(PATH.dashboard_update_status, obj, 384);
}

function first_dir(path) {
	let r = run_capture('find ' + sh_quote(path) + ' -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1');
	return trim(split(r.out || '', '\n')[0] || '');
}

function update_dashboard(cfg, opts) {
	opts = opts || {};
	let mirror = opts.mirror != null ? opts.mirror : ((cfg && cfg.main && cfg.main.core_mirror) || '');
	if (system([ 'sh', '-c', 'command -v unzip >/dev/null 2>&1' ]) != 0) {
		let err = '缺少 unzip 命令，请先安装 unzip（busybox 通常自带）';
		write_dashboard_status('error', { error: err });
		return { ok: false, error: err };
	}
	let url = dashboard_archive_url(mirror);
	write_dashboard_status('downloading', { message: '下载 ' + url, url: url });
	mkdir_p(PATH.run_dir);
	let zip = PATH.run_dir + '/dashboard.zip';
	let dir = PATH.run_dir + '/dashboard-extract';
	system([ 'rm', '-rf', dir ]);
	mkdir_p(dir);
	let r = run_capture('curl -fsSL --connect-timeout 15 --max-time 300 -o ' + sh_quote(zip) + ' ' + sh_quote(url));
	if (!r.ok) {
		write_dashboard_status('error', { error: '下载失败' });
		return { ok: false, error: '下载失败，请检查网络或镜像' };
	}
	let st = stat(zip);
	if (!st || !st.size) {
		write_dashboard_status('error', { error: '下载文件为空' });
		return { ok: false, error: '下载文件为空' };
	}
	if (system([ 'unzip', '-q', '-o', zip, '-d', dir ]) != 0 && system([ 'unzip', '-q', zip, '-d', dir ]) != 0) {
		write_dashboard_status('error', { error: '解包失败' });
		return { ok: false, error: '解包失败' };
	}
	let top = first_dir(dir);
	if (!length(top) || !file_exists(top + '/index.html')) {
		write_dashboard_status('error', { error: '面板包结构异常' });
		return { ok: false, error: '面板包结构异常（未找到 index.html）' };
	}
	write_dashboard_status('installing', { message: '安装面板文件' });
	let target = dashboard_dir();
	let stage = PATH.etc + '/ui.new';
	system([ 'rm', '-rf', stage ]);
	mkdir_p(stage);
	if (system([ 'cp', '-a', top + '/.', stage ]) != 0 && system([ 'sh', '-c', 'cp -r ' + sh_quote(top) + '/. ' + sh_quote(stage) ]) != 0) {
		write_dashboard_status('error', { error: '复制面板文件失败' });
		return { ok: false, error: '复制面板文件失败' };
	}
	system([ 'rm', '-rf', target ]);
	if (rename(stage, target) !== true) {
		write_dashboard_status('error', { error: '替换面板目录失败' });
		return { ok: false, error: '替换面板目录失败' };
	}
	system([ 'rm', '-rf', dir ]);
	try { unlink(zip); } catch (e) {}
	write_dashboard_status('done', { size: st.size });
	return { ok: true, path: target, size: st.size };
}

/* Percent-encode everything outside the unreserved set (names contain spaces, CJK, emoji). */
function pct(s) {
	s = s == null ? '' : s;
	let out = '';
	for (let i = 0; i < length(s); i++) {
		let b = ord(substr(s, i, 1));
		if ((b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) ||
			b == 45 || b == 46 || b == 95 || b == 126)
			out += chr(b);
		else
			out += sprintf('%%%02X', b);
	}
	return out;
}

function last_delay(info) {
	let h = info && info.history;
	if (type(h) != 'array' || !length(h)) return 0;
	let last = h[length(h) - 1];
	return (last && int(last.delay)) || 0;
}

function api(cfg, method, path, body) {
	let p = panel_config(cfg);
	if (!p.enabled) return { ok: false, error: '面板未启用' };
	let host = (p.listen == '0.0.0.0' || p.listen == '::' || p.listen == '[::]') ? '127.0.0.1' : p.listen;
	let url = 'http://' + host + ':' + p.port + path;
	let cmd = 'curl -sS --connect-timeout 3 --max-time 10 -X ' + method;
	if (length(p.secret)) cmd += ' -H ' + sh_quote('Authorization: Bearer ' + p.secret);
	if (body != null) cmd += ' -H ' + sh_quote('Content-Type: application/json') + ' --data ' + sh_quote(sprintf('%J', body));
	cmd += ' ' + sh_quote(url);
	let r = run_capture(cmd);
	if (!r.ok) return { ok: false, error: 'Clash API 不可达', detail: trim(r.out) };
	let out = trim(r.out);
	if (!length(out)) return { ok: true, data: null };
	let data = null;
	try { data = json(out); } catch (e) { data = null; }
	if (data == null) return { ok: false, error: 'Clash API 返回非 JSON', detail: substr(out, 0, 200) };
	return { ok: true, data: data };
}

function proxy_groups(data) {
	let list = [];
	let proxies = (data && type(data.proxies) == 'object') ? data.proxies : {};
	for (let name in keys(proxies)) {
		let p = proxies[name];
		if (!p || type(p) != 'object' || type(p.all) != 'array' || !length(p.all)) continue;
		let t = p.type || '';
		if (t != 'selector' && t != 'urltest' && t != 'fallback' && t != 'load-balance') continue;
		let members = [];
		for (let m in p.all) {
			let info = proxies[m] || {};
			push(members, { name: m, type: info.type || '', delay: last_delay(info) });
		}
		push(list, { name: name, type: t, now: p.now || '', members: members });
	}
	return list;
}

function connection_list(data, limit) {
	let out = [];
	let list = (data && type(data.connections) == 'array') ? data.connections : [];
	let max = int(limit || 30);
	for (let c in list) {
		let meta = (c && type(c.metadata) == 'object') ? c.metadata : {};
		let chains = [];
		if (type(c.chains) == 'array') for (let ch in c.chains) push(chains, ch);
		push(out, {
			id: c.id || '',
			host: meta.host || meta.destinationIP || '',
			dest: (meta.destinationIP || '') + (meta.destinationPort ? ':' + meta.destinationPort : ''),
			network: meta.network || '',
			type: meta.type || '',
			source: meta.sourceIP || '',
			rule: c.rule || '',
			payload: c.rulePayload || '',
			chains: chains,
			upload: int(c.upload || 0),
			download: int(c.download || 0),
			start: c.start || ''
		});
		if (length(out) >= max) break;
	}
	return {
		download: int((data && data.downloadTotal) || 0),
		upload: int((data && data.uploadTotal) || 0),
		connections: out
	};
}

function panel_status(cfg) {
	let p = panel_config(cfg);
	let dash = dashboard_selected(cfg);
	let dash_ready = dashboard_installed();
	if (!p.enabled) return { ok: false, enabled: false, error: '面板未启用', dashboard: dash, dashboard_installed: dash_ready };
	if (!length(p.secret)) return { ok: false, enabled: true, error: '未设置 API 密钥', port: p.port, listen: p.listen, dashboard: dash, dashboard_installed: dash_ready };
	let v = api(cfg, 'GET', '/version');
	if (!v.ok) return { ok: false, enabled: true, error: v.error || 'Clash API 不可达', port: p.port, listen: p.listen, dashboard: dash, dashboard_installed: dash_ready };
	let conns = api(cfg, 'GET', '/connections');
	let conf = api(cfg, 'GET', '/configs');
	return {
		ok: true,
		enabled: true,
		version: (v.data && v.data.version) || '',
		mode: (conf.ok && conf.data && conf.data.mode) || '',
		download: conns.ok ? int(((conns.data || {}).downloadTotal) || 0) : 0,
		upload: conns.ok ? int(((conns.data || {}).uploadTotal) || 0) : 0,
		count: conns.ok ? length(((conns.data || {}).connections) || []) : 0,
		port: p.port,
		listen: p.listen,
		secret: p.secret,
		dashboard: dash,
		dashboard_installed: dash_ready
	};
}

function panel_proxies(cfg) {
	let r = api(cfg, 'GET', '/proxies');
	if (!r.ok) return r;
	return { ok: true, groups: proxy_groups(r.data) };
}

function panel_select(cfg, group, node) {
	if (!length(trim(group || '')) || !length(trim(node || '')))
		return { ok: false, error: '缺少代理组或节点' };
	let r = api(cfg, 'PUT', '/proxies/' + pct(group), { name: node });
	return r.ok ? { ok: true, group: group, now: node } : r;
}

function panel_delay(cfg, group) {
	let p = panel_config(cfg);
	let url = delay_url(cfg, p);
	let r = api(cfg, 'GET', '/proxies');
	if (!r.ok) return r;
	let proxies = r.data.proxies || {};
	let gp = proxies[group];
	if (!gp || type(gp.all) != 'array') return { ok: false, error: '代理组不存在' };
	let delays = {};
	let n = 0;
	for (let m in gp.all) {
		if (n++ >= MAX_DELAY_MEMBERS) break;
		let d = api(cfg, 'GET', '/proxies/' + pct(m) + '/delay?timeout=2500&url=' + pct(url));
		delays[m] = (d.ok && d.data) ? int(d.data.delay || 0) : 0;
	}
	return { ok: true, group: group, delays: delays };
}

function panel_connections(cfg, limit) {
	let r = api(cfg, 'GET', '/connections');
	if (!r.ok) return r;
	let list = connection_list(r.data, limit || 30);
	list.ok = true;
	return list;
}

function panel_close(cfg, id) {
	if (!length(trim(id || ''))) return { ok: false, error: '缺少连接 ID' };
	let r = api(cfg, 'DELETE', '/connections/' + pct(id));
	return r.ok ? { ok: true } : r;
}

/* Random hex secret for Clash API authentication. */
function random_secret() {
	let r = run_capture('head -c 16 /dev/urandom 2>/dev/null | md5sum 2>/dev/null');
	let s = trim(split(r.out || '', ' ')[0] || '');
	if (match(s, /^[0-9a-f]{16,}$/)) return substr(s, 0, 24);
	r = run_capture('head -c 12 /dev/urandom 2>/dev/null | od -An -tx1 2>/dev/null | tr -d " \\n"');
	s = trim(r.out || '');
	if (match(s, /^[0-9a-f]{16,}$/)) return substr(s, 0, 24);
	return sprintf('%08x%08x', int(time()), int(time() / 7));
}

export {
	DEFAULT_PORT, DEFAULT_LISTEN, DEFAULT_DELAY_URL, DASHBOARD_REPO, DASHBOARD_ARCHIVE,
	panel_config, delay_url, pct, last_delay, api, proxy_groups, connection_list,
	panel_status, panel_proxies, panel_select, panel_delay, panel_connections, panel_close,
	dashboard_dir, dashboard_installed, dashboard_archive_url, dashboard_selected,
	dashboard_status, update_dashboard, random_secret
};