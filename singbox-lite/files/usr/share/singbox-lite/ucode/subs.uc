'use strict';

import { trim, split_lines, split_csv, write_text, read_text, shell_http_get, parse_subscription_userinfo, PATH, sh_quote, run_capture, mkdir_p, file_exists } from 'sbx_common';
import { unlink } from 'fs';
import { parse_link, b64_decode_text, clash_to_outbound, strip_null } from 'sbx_links';

const MAX_BODY = 5 * 1024 * 1024;

/* 这些字段在 sing-box schema 里必须是对象；空对象/空数组都算脏字段。 */
const OPTIONAL_OBJECT_FIELDS = [ 'transport', 'multiplex', 'tls', 'headers', 'obfs' ];

/* 缺必填凭据的节点运行时不可用，部分类型（ss/tuic）还会让 check 失败；解析阶段直接跳过。 */
const REQUIRED_CREDENTIALS = {
	anytls: [ 'password' ],
	hysteria2: [ 'password' ],
	trojan: [ 'password' ],
	tuic: [ 'uuid', 'password' ],
	vless: [ 'uuid' ],
	vmess: [ 'uuid' ]
};

function looks_json(s) {
	let t = trim(s);
	return substr(t, 0, 1) == '{' || substr(t, 0, 1) == '[';
}

function looks_clash(s) {
	for (let line in split_lines(s))
		if (match(line, /^proxies\s*:/))
			return true;
	return false;
}

function detect_format(body) {
	let s = trim(body);
	if (!length(s)) return 'empty';
	if (looks_json(s)) return 'json';
	if (looks_clash(s)) return 'clash';
	if (index(s, '://') >= 0) return 'uri';
	let decoded = b64_decode_text(s);
	if (decoded && length(decoded)) {
		if (looks_json(decoded)) return 'json-base64';
		if (looks_clash(decoded)) return 'clash-base64';
		if (index(decoded, '://') >= 0) return 'uri-base64';
	}
	return 'unknown';
}

/* 可选字段类型不对（如 "transport": []）或为空对象，一律清成 null 交给 strip_null 删除。 */
function clean_optional_objects(o) {
	for (let k in OPTIONAL_OBJECT_FIELDS) {
		let v = o[k];
		if (v == null) continue;
		if (type(v) != 'object' || !length(keys(v))) o[k] = null;
	}
}

function has_text(v) {
	return type(v) == 'string' && length(trim(v)) > 0;
}

/* 未知类型不在表里，返回 true，保留原有「无法识别」告警行为。 */
function has_required_credentials(out, t) {
	if (t == 'shadowsocks') {
		/* sing-box 接受 method=none 的无密码 SS 节点，其他加密方式必须有 password。 */
		if (!has_text(out.method)) return false;
		return lc(trim(out.method)) == 'none' || has_text(out.password);
	}
	let need = REQUIRED_CREDENTIALS[t];
	if (!need) return true;
	for (let k in need)
		if (!has_text(out[k])) return false;
	return true;
}

function node_from_outbound(out) {
	if (!out || type(out) != 'object') return null;
	let t = lc(out.type || '');
	if (t == 'selector' || t == 'urltest' || t == 'direct' || t == 'block' || t == 'dns')
		return null;
	if (!out.server || !out.server_port) return null;
	if (!has_required_credentials(out, t)) return null;
	let copy = {};
	for (let k in keys(out)) if (k != 'tag' && k != 'name') copy[k] = out[k];
	clean_optional_objects(copy);
	return strip_null({
		name: out.tag || out.name || out.server,
		type: out.type,
		server: out.server,
		server_port: int(out.server_port),
		outbound: copy
	});
}

function parse_json_body(body) {
	let data;
	try { data = json(body); } catch (e) { return { ok: false, error: 'JSON 解析失败' }; }
	let list = [];
	if (type(data) == 'array') {
		list = data;
	} else if (data && type(data.outbounds) == 'array') {
		list = data.outbounds;
	} else if (data && type(data.proxies) == 'array') {
		list = data.proxies;
	} else {
		return { ok: false, error: 'JSON 中找不到 outbounds/proxies' };
	}
	let nodes = [], warnings = [];
	for (let item in list) {
		let n = null, skipped = null;
		if (item && item.type && item.server_port != null) n = node_from_outbound(item);
		else if (item && item.type && (item.port != null || item.name)) {
			let o = clash_to_outbound(item);
			if (o) {
				if (!o.server || !o.server_port)
					skipped = sprintf('跳过缺少服务器地址的节点：%s', item.name || item.type || '');
				else {
					clean_optional_objects(o);
					if (!has_required_credentials(o, lc(o.type || '')))
						skipped = sprintf('跳过缺少凭据的节点：%s（%s:%s）', item.name || o.server || '', o.server || '', o.server_port);
					else
						n = { name: item.name || o.server, type: o.type, server: o.server, server_port: o.server_port, outbound: o };
				}
			}
		}
		if (n) push(nodes, n);
		else if (skipped) push(warnings, skipped);
		else if (!(item && item.type && match(lc(item.type), /^(selector|urltest|direct|block|dns)$/)))
			push(warnings, '跳过无法识别的节点');
	}
	return { ok: length(nodes) > 0, nodes: nodes, warnings: warnings, error: length(nodes) ? null : '没有解析到节点' };
}

function parse_clash_body(body) {
	let yq = run_capture('command -v yq 2>/dev/null');
	if (!yq.ok || !length(trim(yq.out)))
		return { ok: false, error: '未安装 yq，无法解析 Clash 订阅；请 apk add yq 或改用 URI/JSON 订阅' };
	mkdir_p(PATH.run_dir);
	let tmp = PATH.run_dir + '/clash-sub.yaml';
	if (!write_text(tmp, body, 384)) return { ok: false, error: '写入临时文件失败' };
	let r = run_capture('yq -o=json eval ' + sh_quote('.proxies') + ' ' + sh_quote(tmp) + ' 2>/dev/null');
	try { unlink(tmp); } catch (e) {}
	if (!r.ok || !length(trim(r.out))) return { ok: false, error: 'yq 解析失败' };
	let list;
	try { list = json(r.out); } catch (e) { return { ok: false, error: 'yq 输出不是 JSON' }; }
	if (type(list) != 'array') return { ok: false, error: 'Clash 订阅没有 proxies 数组' };
	let nodes = [], warnings = [];
	for (let item in list) {
		if (!item || type(item) != 'object' || !item.type || !item.server) continue;
		let out = clash_to_outbound(item);
		if (!out) { push(warnings, sprintf('不支持的 Clash 协议：%s（%s）', item.type, item.name || '')); continue; }
		clean_optional_objects(out);
		if (!has_required_credentials(out, lc(out.type || ''))) {
			push(warnings, sprintf('跳过缺少凭据的节点：%s（%s:%s）', item.name || out.server, out.server, out.server_port));
			continue;
		}
		push(nodes, { name: item.name || item.server, type: out.type, server: out.server, server_port: out.server_port, outbound: out });
	}
	return { ok: length(nodes) > 0, nodes: nodes, warnings: warnings, error: length(nodes) ? null : '没有解析到 Clash 节点' };
}

function parse_uri_body(body) {
	let nodes = [], warnings = [];
	for (let line in split_lines(body)) {
		if (substr(line, 0, 1) == '#') continue;
		if (index(line, '://') < 0) continue;
		let p = parse_link(line);
		if (!p.ok) { push(warnings, sprintf('跳过节点：%s', p.error)); continue; }
		push(nodes, { name: p.name, type: p.type, server: p.server, server_port: p.server_port, outbound: p.outbound });
	}
	return { ok: length(nodes) > 0, nodes: nodes, warnings: warnings, error: length(nodes) ? null : '没有解析到节点' };
}

function parse_body(body, format) {
	format = format || 'auto';
	if (!length(trim(body))) return { ok: false, error: '订阅内容为空' };
	if (length(body) > MAX_BODY) return { ok: false, error: '订阅内容超过 5MB 限制' };
	if (substr(trim(body), 0, 1) == '<') return { ok: false, error: '订阅返回了 HTML 页面（可能需要正确的 UA 或 token）' };
	let detected = detect_format(body);
	if (format == 'auto') format = detected;
	if (format == 'json' || format == 'singbox') return parse_json_body(body);
	if (format == 'clash') return parse_clash_body(body);
	if (format == 'uri') return parse_uri_body(body);
	if (format == 'json-base64' || format == 'clash-base64' || format == 'uri-base64') {
		let decoded = b64_decode_text(body);
		if (!decoded) return { ok: false, error: 'base64 解码失败' };
		if (format == 'json-base64') return parse_json_body(decoded);
		if (format == 'clash-base64') return parse_clash_body(decoded);
		return parse_uri_body(decoded);
	}
	if (detected == 'unknown') return { ok: false, error: '无法识别订阅格式' };
	// Retry with detected base64 variants.
	if (detected == 'json-base64') return parse_json_body(b64_decode_text(body));
	if (detected == 'clash-base64') return parse_clash_body(b64_decode_text(body));
	if (detected == 'uri-base64') return parse_uri_body(b64_decode_text(body));
	return { ok: false, error: '无法识别订阅格式' };
}

function fetch_subscription(section, url, ua, format) {
	if (!length(url || '')) return { ok: false, error: '订阅 URL 为空' };
	mkdir_p(PATH.run_dir);
	mkdir_p(PATH.subs_dir);
	mkdir_p(PATH.meta_dir);
	let body_file = PATH.run_dir + '/' + section + '.body';
	let hdr_file = PATH.run_dir + '/' + section + '.hdr';
	/* 在下载阶段就用 --max-filesize 限流，别等整个 body 写满 /tmp。 */
	let r = shell_http_get(url, body_file, hdr_file, ua || 'sing-box/1.14', 120, MAX_BODY);
	if (!r.ok || trim(r.out) != '200') {
		let code = trim(r.out);
		try { unlink(body_file); } catch (e) {}
		if (code == '200')
			return { ok: false, error: '下载失败：内容超过 5MB 限制' };
		return { ok: false, error: '下载失败：HTTP ' + code };
	}
	let body = read_text(body_file, '');
	let parsed = parse_body(body, format);
	if (!parsed.ok) return parsed;
	let userinfo = parse_subscription_userinfo(hdr_file);
	let raw_path = PATH.subs_dir + '/' + section + '.raw';
	let meta_path = PATH.meta_dir + '/' + section + '.json';
	write_text(raw_path, body, 384);
	write_text(meta_path, sprintf('%J', {
		section: section,
		updated: time(),
		userinfo: userinfo,
		nodes: parsed.nodes,
		warnings: parsed.warnings
	}), 384);
	return { ok: true, nodes: parsed.nodes, warnings: parsed.warnings, userinfo: userinfo, raw_path: raw_path, meta_path: meta_path };
}

export { detect_format, parse_body, fetch_subscription };
