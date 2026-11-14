'use strict';

import { trim, split_lines, split_csv, write_text, read_text, shell_http_get, parse_subscription_userinfo, PATH, sh_quote, run_capture, mkdir_p, file_exists } from 'sbx_common';
import { unlink } from 'fs';
import { parse_link, b64_decode_text, clash_to_outbound, strip_null } from 'sbx_links';

const MAX_BODY = 5 * 1024 * 1024;

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

function node_from_outbound(out) {
	if (!out || type(out) != 'object') return null;
	let t = lc(out.type || '');
	if (t == 'selector' || t == 'urltest' || t == 'direct' || t == 'block' || t == 'dns')
		return null;
	if (!out.server || !out.server_port) return null;
	let copy = {};
	for (let k in keys(out)) if (k != 'tag' && k != 'name') copy[k] = out[k];
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
		let n = null;
		if (item && item.type && item.server_port != null) n = node_from_outbound(item);
		else if (item && item.type && (item.port != null || item.name)) {
			let o = clash_to_outbound(item);
			if (o) n = { name: item.name || o.server, type: o.type, server: o.server, server_port: o.server_port, outbound: o };
		}
		if (n) push(nodes, n);
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
	let r = shell_http_get(url, body_file, hdr_file, ua || 'sing-box/1.14', 120);
	if (!r.ok || trim(r.out) != '200') {
		try { unlink(body_file); } catch (e) {}
		return { ok: false, error: '下载失败：HTTP ' + trim(r.out) };
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
