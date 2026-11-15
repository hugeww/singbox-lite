'use strict';

import { readfile, writefile, rename, chmod, mkdir, stat, access, popen, unlink, dirname } from 'fs';

const VERSION = '0.1.0';

const PATH = {
	etc: getenv('SINGBOX_LITE_ETC') || '/etc/singbox-lite',
	lib: getenv('SINGBOX_LITE_LIB') || '/usr/share/singbox-lite',
	config: getenv('SINGBOX_LITE_CONFIG') || '/etc/config/singbox-lite',
	init: getenv('SINGBOX_LITE_INIT') || '/etc/init.d/singbox-lite',
	core: getenv('SINGBOX_LITE_CORE') || '/usr/libexec/singbox-lite/sing-box',
	system_core: '/usr/bin/sing-box',
	log_dir: getenv('SINGBOX_LITE_LOG_DIR') || '/var/log/singbox-lite',
	run_dir: getenv('SINGBOX_LITE_RUN_DIR') || '/tmp/singbox-lite'
};

PATH.config_json = PATH.etc + '/config.json';
PATH.config_bak = PATH.etc + '/config.json.bak';
PATH.subs_dir = PATH.etc + '/subs';
PATH.meta_dir = PATH.etc + '/meta';
PATH.rulesets_dir = PATH.etc + '/rulesets';
PATH.builtin_rulesets_dir = PATH.lib + '/rulesets';
PATH.core_bak = PATH.core + '.bak';
PATH.core_meta = PATH.etc + '/core.json';
PATH.core_update_status = PATH.run_dir + '/core-update.json';
PATH.plugin_update_status = PATH.run_dir + '/plugin-update.json';
PATH.dashboard_update_status = PATH.run_dir + '/dashboard-update.json';
PATH.releases_cache = PATH.run_dir + '/releases.json';
PATH.refresh_status = PATH.run_dir + '/refresh.json';
PATH.cron_file = getenv('SINGBOX_LITE_CRON_FILE') || '/etc/crontabs/root';
PATH.lock = PATH.run_dir + '/lock';

function trim(s) {
	return s == null ? '' : ltrim(rtrim(s));
}

function split_lines(s) {
	let lines = [];
	for (let line in split(s == null ? '' : s, '\n')) {
		line = trim(line);
		if (length(line))
			push(lines, line);
	}
	return lines;
}

function split_csv(s) {
	let out = [];
	for (let item in split(s == null ? '' : s, ',')) {
		item = trim(item);
		if (length(item))
			push(out, item);
	}
	return out;
}

function file_exists(path) {
	return access(path) === true;
}

function read_text(path, def) {
	try {
		path = readfile(path);
		return path == null ? (def == null ? '' : def) : path;
	} catch (e) {
		return def == null ? '' : def;
	}
}

function read_json(path, def) {
	try {
		let raw = readfile(path);
		if (raw == null || !length(trim(raw)))
			return def == null ? null : def;
		let data = json(raw);
		return data == null ? (def == null ? null : def) : data;
	} catch (e) {
		return def == null ? null : def;
	}
}

function mkdir_p(path) {
	if (!length(path) || path == '/')
		return true;
	let parts = split(path, '/');
	let cur = '';
	for (let part in parts) {
		if (!length(part))
			continue;
		cur += '/' + part;
		if (access(cur) !== true) {
			try { mkdir(cur); } catch (e) { if (access(cur) !== true) return false; }
		}
	}
	return true;
}

function chmod_file(path, mode) {
	try { chmod(path, mode); return true; } catch (e) { return false; }
}

function getpid() {
	let p = popen('echo $$');
	if (!p) return '0';
	let v = trim(p.read('all'));
	p.close();
	return v;
}

function write_text(path, content, mode) {
	mkdir_p(dirname(path));
	let tmp = path + '.tmp.' + getpid();
	let written = writefile(tmp, content);
	if (written == null)
		return false;
	chmod_file(tmp, mode == null ? 384 : mode); /* 0600 default */
	if (rename(tmp, path) !== true) {
		try { unlink(tmp); } catch (e) {}
		return false;
	}
	return true;
}

function write_json(path, obj, mode) {
	return write_text(path, sprintf('%J', obj), mode == null ? 384 : mode);
}

function sh_quote(s) {
	return "'" + replace(s == null ? '' : s, "'", "'\\''") + "'";
}

function run_capture(cmd) {
	let p = popen(cmd);
	if (!p) return { ok: false, out: '' };
	let out = p.read('all');
	let rc = p.close();
	return { ok: rc == 0, out: out == null ? '' : out, rc: rc };
}

function run(argv) {
	return system(argv);
}

function log_app(message) {
	mkdir_p(PATH.log_dir);
	let line = sprintf('%s %s\n', now_string(), message);
	let file = PATH.log_dir + '/app.log';
	try {
		let old = readfile(file);
		if (old == null) old = '';
		if (length(old) > 1024 * 1024)
			old = substr(old, length(old) - 512 * 1024);
		writefile(file, old + line);
	} catch (e) {}
}

function now_string() {
	let r = run_capture("date '+%Y-%m-%d %H:%M:%S'");
	return trim(r.out);
}

function now_epoch() {
	return time();
}

function human_size(bytes) {
	bytes = int(bytes);
	if (bytes < 1024) return sprintf('%d B', bytes);
	if (bytes < 1024 * 1024) return sprintf('%.1f KB', bytes / 1024);
	if (bytes < 1024 * 1024 * 1024) return sprintf('%.1f MB', bytes / 1024 / 1024);
	return sprintf('%.1f GB', bytes / 1024 / 1024 / 1024);
}

function parse_bool(v, def) {
	if (v == null || v == '') return def == null ? false : def;
	if (v === true || v === 1 || v === '1' || v === 'true' || v === 'yes' || v === 'on')
		return true;
	return false;
}

function fnv1a32(s) {
	let h = 0x811c9dc5;
	for (let i = 0; i < length(s); i++) {
		h = h ^ ord(substr(s, i, 1));
		h = (h * 0x01000193) & 0xffffffff;
	}
	return sprintf('%08x', h);
}

function stable_id(parts) {
	return fnv1a32(join('|', parts));
}

/*
 * Download with curl. `max_size`（字节，可选）通过 --max-filesize 在传输过程中
 * 生效，避免超大响应先把 /tmp 写满、再由调用方事后检查；老调用方不传该参数，
 * 行为保持不变。
 */
function shell_http_get(url, out, header_file, ua, timeout, max_size) {
	mkdir_p(dirname(out));
	mkdir_p(dirname(header_file));
	max_size = int(max_size || 0);
	let cmd = 'curl --proto ' + sh_quote('=https,http') + ' -fsSL' +
		' -H ' + sh_quote('Accept-Encoding: identity') +
		' --connect-timeout 10 --max-time ' + int(timeout || 60) +
		(max_size > 0 ? ' --max-filesize ' + max_size : '') +
		' -A ' + sh_quote(ua || 'sing-box/1.14') +
		' -D ' + sh_quote(header_file) +
		' -o ' + sh_quote(out) +
		' -w ' + sh_quote('%{http_code}') +
		' ' + sh_quote(url);
	return run_capture(cmd);
}

function header_value(path, name) {
	let raw = read_text(path, '');
	let lower = lc(name) + ':';
	for (let line in split(raw, '\n')) {
		line = trim(line);
		if (lc(substr(line, 0, length(lower))) == lower)
			return trim(substr(line, length(lower)));
	}
	return '';
}

function parse_subscription_userinfo(path) {
	let info = header_value(path, 'subscription-userinfo');
	let result = {};
	if (!length(info)) return result;
	for (let part in split(info, ';')) {
		part = trim(part);
		let kv = split(part, '=');
		if (length(kv) < 2) continue;
		let k = trim(kv[0]);
		let v = trim(substr(part, length(k) + 1));
		if (k == 'expire' || k == 'upload' || k == 'download' || k == 'total')
			result[k] = int(v);
	}
	if (result.upload != null && result.download != null)
		result.used = result.upload + result.download;
	if (result.total != null && result.used != null)
		result.available = result.total - result.used;
	if (result.expire != null)
		result.expire_text = run_capture("date -d '@" + int(result.expire) + "' '+%Y-%m-%d %H:%M:%S'").out;
	return result;
}

function fail(message) {
	return { ok: false, error: message };
}

function ok(data) {
	let result = { ok: true };
	if (data != null) {
		for (let k in keys(data))
			result[k] = data[k];
	}
	return result;
}

export { VERSION, PATH, trim, split_lines, split_csv, file_exists, read_text, read_json, mkdir_p, chmod_file, getpid, write_text, write_json, sh_quote, run_capture, run, log_app, now_string, now_epoch, human_size, parse_bool, fnv1a32, stable_id, shell_http_get, header_value, parse_subscription_userinfo, fail, ok };
