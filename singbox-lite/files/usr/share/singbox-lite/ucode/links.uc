'use strict';

import { trim, split_csv } from 'sbx_common';

function lc2(s) { return lc(s == null ? '' : s); }

function strip_null(v) {
	if (type(v) == 'object') {
		let out = {};
		for (let k in keys(v)) {
			if (v[k] == null) continue;
			let x = strip_null(v[k]);
			if (x != null) out[k] = x;
		}
		return out;
	}
	if (type(v) == 'array') {
		let out = [];
		for (let x in v) {
			let y = strip_null(x);
			if (y != null) push(out, y);
		}
		return out;
	}
	return v;
}

function url_decode(s) {
	s = s == null ? '' : s;
	let out = '';
	for (let i = 0; i < length(s); i++) {
		let c = substr(s, i, 1);
		if (c == '%' && i + 2 < length(s)) {
			let hex = substr(s, i + 1, 2);
			if (match(hex, /^[0-9a-fA-F]{2}$/)) {
				out += hexdec(hex);
				i += 2;
				continue;
			}
		}
		if (c == '+') c = ' ';
		out += c;
	}
	return out;
}

function b64_normalize(s) {
	s = replace(s == null ? '' : s, /[\r\n\t ]/g, '');
	s = replace(s, /-/g, '+');
	s = replace(s, /_/g, '/');
	while (length(s) % 4)
		s += '=';
	return s;
}

function b64_decode_text(s) {
	try {
		let d = b64dec(b64_normalize(s));
		return d == null ? null : d;
	} catch (e) {
		return null;
	}
}

function first_index(s, needle) {
	let i = index(s, needle);
	return i == null ? -1 : i;
}

function split_query(q) {
	let out = {};
	if (!length(q)) return out;
	for (let part in split(q, '&')) {
		let eq = first_index(part, '=');
		let k, v;
		if (eq < 0) {
			k = url_decode(part);
			v = '';
		} else {
			k = url_decode(substr(part, 0, eq));
			v = url_decode(substr(part, eq + 1));
		}
		if (length(k)) out[k] = v;
	}
	return out;
}

function parse_url(link) {
	let s = trim(link);
	let scheme_pos = first_index(s, '://');
	if (scheme_pos < 1) return null;
	let scheme = lc2(substr(s, 0, scheme_pos));
	let rest = substr(s, scheme_pos + 3);
	let fragment = '';
	let hpos = first_index(rest, '#');
	if (hpos >= 0) {
		fragment = url_decode(substr(rest, hpos + 1));
		rest = substr(rest, 0, hpos);
	}
	let query = '';
	let qpos = first_index(rest, '?');
	if (qpos >= 0) {
		query = substr(rest, qpos + 1);
		rest = substr(rest, 0, qpos);
	}
	let path = '';
	let slash = first_index(rest, '/');
	if (slash >= 0) {
		path = substr(rest, slash);
		rest = substr(rest, 0, slash);
	}
	let userinfo = '';
	let at = rindex(rest, '@');
	if (at != null && at >= 0) {
		userinfo = substr(rest, 0, at);
		rest = substr(rest, at + 1);
	}
	let host = rest;
	let port = '';
	if (substr(rest, 0, 1) == '[') {
		let close = first_index(rest, ']');
		if (close >= 0) {
			host = substr(rest, 1, close - 1);
			if (substr(rest, close + 1, 1) == ':')
				port = substr(rest, close + 2);
		}
	} else {
		let colon = rindex(rest, ':');
		if (colon != null && colon >= 0) {
			host = substr(rest, 0, colon);
			port = substr(rest, colon + 1);
		}
	}
	return {
		scheme: scheme, userinfo: userinfo, host: host, port: port,
		path: path, query: query, params: split_query(query), name: fragment
	};
}

function tls_settings(params, server, force) {
	let security = lc2(params.security || params.tls || (force ? 'tls' : ''));
	if (!length(security) || security == 'none' || security == 'false' || security == '0')
		return null;
	let tls = {
		enabled: true,
		server_name: params.sni || params.peer || params.servername || server
	};
	if (params.allowinsecure == '1' || params.insecure == '1' || params['skip-cert-verify'] == '1' || params.allowinsecure == 'true')
		tls.insecure = true;
	if (params.alpn) tls.alpn = split_csv(params.alpn);
	if (params.fp) tls.utls = { enabled: true, fingerprint: params.fp };
	if (security == 'reality') {
		if (!tls.utls) tls.utls = { enabled: true, fingerprint: 'chrome' };
		tls.reality = {
			enabled: true,
			public_key: params.pbk || params['public-key'] || '',
			short_id: params.sid || params['short-id'] || ''
		};
	}
	return strip_null(tls);
}

function transport_settings(params, default_host) {
	let net = lc2(params.net || params.type || params.network || 'tcp');
	if (net == 'ws' || net == 'websocket') {
		return strip_null({
			type: 'ws',
			path: params.path || '/',
			headers: { Host: params.host || default_host }
		});
	}
	if (net == 'grpc') {
		return strip_null({ type: 'grpc', service_name: params.servicename || params.serviceName || params.path || '' });
	}
	if (net == 'h2' || net == 'http') {
		return strip_null({ type: 'http', host: split_csv(params.host || default_host), path: params.path || '/' });
	}
	return null;
}

function mk_node(type, name, server, port, outbound, warnings) {
	return {
		ok: true,
		name: length(name) ? name : (server + ':' + port),
		type: type,
		server: server,
		server_port: int(port),
		outbound: strip_null(outbound),
		warnings: warnings || []
	};
}

function parse_vmess(link, u) {
	let raw = b64_decode_text(substr(link, length('vmess://')));
	if (!raw) return { ok: false, error: 'vmess base64 decode failed' };
	let o;
	try { o = json(raw); } catch (e) { return { ok: false, error: 'vmess JSON parse failed' }; }
	if (!o || !o.add) return { ok: false, error: 'vmess missing add' };
	let p = {
		net: o.net, type: o.type, host: o.host, path: o.path,
		tls: o.tls, sni: o.sni, fp: o.fp, alpn: o.alpn,
		allowinsecure: o.allowInsecure || o.insecure || ''
	};
	let out = {
		type: 'vmess',
		server: o.add,
		server_port: int(o.port),
		uuid: o.id,
		security: o.scy || 'auto',
		alter_id: int(o.aid || 0),
		tls: tls_settings(p, o.add, false),
		transport: transport_settings(p, o.add)
	};
	return mk_node('vmess', o.ps || u.name, o.add, o.port, out, []);
}

function parse_vless(u) {
	if (!length(u.userinfo)) return { ok: false, error: 'vless missing uuid' };
	let p = u.params;
	let out = {
		type: 'vless',
		server: u.host,
		server_port: int(u.port || 443),
		uuid: url_decode(u.userinfo),
		flow: p.flow || null,
		tls: tls_settings(p, u.host, false),
		transport: transport_settings(p, u.host)
	};
	return mk_node('vless', u.name, u.host, u.port || 443, out, []);
}

function parse_trojan(u) {
	if (!length(u.userinfo)) return { ok: false, error: 'trojan missing password' };
	let p = u.params;
	let out = {
		type: 'trojan',
		server: u.host,
		server_port: int(u.port || 443),
		password: url_decode(u.userinfo),
		tls: tls_settings(p, u.host, true),
		transport: transport_settings(p, u.host)
	};
	return mk_node('trojan', u.name, u.host, u.port || 443, out, []);
}

function parse_ss(link, u) {
	let raw = substr(link, length('ss://'));
	let fragment = u.name;
	let authority = u.host + (length(u.port) ? ':' + u.port : '');
	if (!length(u.userinfo)) {
		let body = substr(raw, 0, first_index(raw, '#') >= 0 ? first_index(raw, '#') : length(raw));
		let q = first_index(body, '?');
		if (q >= 0) body = substr(body, 0, q);
		let decoded = b64_decode_text(body);
		if (!decoded) return { ok: false, error: 'ss decode failed' };
		let at = rindex(decoded, '@');
		if (at == null || at < 0) return { ok: false, error: 'ss missing host' };
		u.userinfo = substr(decoded, 0, at);
		let hp = substr(decoded, at + 1);
		let colon = rindex(hp, ':');
		if (colon == null || colon < 0) return { ok: false, error: 'ss missing port' };
		u.host = substr(hp, 0, colon);
		u.port = substr(hp, colon + 1);
	}
	let cred = b64_decode_text(u.userinfo);
	if (!cred) {
		cred = url_decode(u.userinfo);
	}
	let colon = first_index(cred, ':');
	if (colon < 0) return { ok: false, error: 'ss missing method/password' };
	let method = substr(cred, 0, colon);
	let password = substr(cred, colon + 1);
	let out = {
		type: 'shadowsocks',
		server: u.host,
		server_port: int(u.port || 8388),
		method: method,
		password: password
	};
	let plugin = u.params.plugin;
	if (length(plugin)) {
		let parts = split(plugin, ';');
		out.plugin = parts[0];
		out.plugin_opts = substr(plugin, length(parts[0]) + 1);
	}
	return mk_node('shadowsocks', fragment || u.name, u.host, u.port || 8388, out, []);
}

/* ---------- Hysteria2 带宽 / 端口跳跃 ---------- */

function scalar_text(v) {
	if (v == null) return '';
	if (type(v) == 'string') return v;
	if (type(v) == 'bool') return v ? 'true' : 'false';
	if (type(v) == 'int' || type(v) == 'double') return sprintf('%s', v);
	return '';
}

function param_blank(v) {
	if (v == null) return true;
	if (type(v) == 'array') return !length(v);
	if (type(v) == 'object') return !length(keys(v));
	return !length(trim(scalar_text(v)));
}

/*
 * Hysteria2 的带宽与端口跳跃在 URI 和 Clash YAML 里命名不统一：URI 常见
 * upmbps/downmbps/mport，Clash 常见 up/down/ports，另有下划线写法。这里按
 * 候选名大小写不敏感地取第一个非空值，返回原始值（字符串/整数/数组）。
 */
function param_value(params, names) {
	if (params == null || type(params) != 'object') return null;
	for (let name in names) {
		if (!param_blank(params[name])) return params[name];
	}
	for (let k in keys(params)) {
		for (let name in names) {
			if (lc2(k) != lc2(name)) continue;
			if (!param_blank(params[k])) return params[k];
		}
	}
	return null;
}

/* 带宽只接受正整数 Mbps（100 / "100" / "100 Mbps" 都行），无效或 <=0 不写字段。 */
function positive_int(v) {
	let n = int(trim(scalar_text(v)));
	return n > 0 ? n : 0;
}

/*
 * 端口跳跃范围统一成 sing-box 的 "起始:结束" 字符串数组。sing-quic 的
 * ParsePorts 要求每一项都必须带 ":"，裸单端口（如 "443"）会被当成非法范围
 * 让节点起不来，所以单端口补成 "443:443"。"1000-2000" / "1000:2000" /
 * 逗号分隔多段都接受；非数字、越界（>65535）或起止颠倒的段直接丢弃，
 * 避免生成过不了校验的配置。
 */
function port_ranges(v) {
	if (type(v) == 'array') {
		let out = [];
		for (let x in v)
			for (let y in port_ranges(x)) push(out, y);
		return out;
	}
	let out = [];
	for (let part in split(replace(trim(scalar_text(v)), /\s+/g, ''), ',')) {
		let m = match(replace(part, /-/g, ':'), /^(\d{1,5})(:(\d{1,5}))?$/);
		if (m == null) continue;
		let lo = int(m[1]);
		let hi = m[3] == null ? lo : int(m[3]);
		if (lo < 1 || hi < lo || hi > 65535) continue;
		push(out, sprintf('%d:%d', lo, hi));
	}
	return out;
}

/*
 * hop_interval 是 Go 时长字符串：URI 一般自带单位（30s），Clash 写的是秒数
 * （30）或秒数区间（15-30）。纯数字补上 "s"，区间取下限（sing-box 的
 * hop_interval_max 不在本次映射范围内），已带单位的原样保留。
 */
function hop_interval_text(v) {
	let s = replace(trim(scalar_text(v)), /\s+/g, '');
	if (!length(s)) return '';
	let m = match(s, /^(\d+)(-\d+)?$/);
	if (m != null) return m[1] + 's';
	return s;
}

function parse_hysteria2(u) {
	if (!length(u.userinfo)) return { ok: false, error: 'hysteria2 missing password' };
	let p = u.params;
	let out = {
		type: 'hysteria2',
		server: u.host,
		server_port: int(u.port || 443),
		password: url_decode(u.userinfo),
		tls: tls_settings(p, u.host, true)
	};
	if (length(p.obfs)) {
		out.obfs = { type: p.obfs, password: p['obfs-password'] || '' };
	}
	/* 带宽：URI 里常见 upmbps/downmbps，也接受 up/down 别名。 */
	let up = positive_int(param_value(p, [ 'upmbps', 'up-mbps', 'up_mbps', 'up' ]));
	if (up > 0) out.up_mbps = up;
	let down = positive_int(param_value(p, [ 'downmbps', 'down-mbps', 'down_mbps', 'down' ]));
	if (down > 0) out.down_mbps = down;
	/* 端口跳跃：mport 是 Hysteria2 分享链接的事实标准写法，ports 为兼容别名。 */
	let ports = port_ranges(param_value(p, [ 'mport', 'ports', 'server_ports', 'server-ports' ]));
	if (length(ports)) out.server_ports = ports;
	let hop = hop_interval_text(param_value(p, [ 'hop-interval', 'hop_interval', 'hopinterval' ]));
	if (length(hop)) out.hop_interval = hop;
	return mk_node('hysteria2', u.name, u.host, u.port || 443, out, []);
}

function parse_tuic(u) {
	if (!length(u.userinfo)) return { ok: false, error: 'tuic missing credentials' };
	let cred = url_decode(u.userinfo);
	let colon = first_index(cred, ':');
	if (colon < 0) return { ok: false, error: 'tuic missing password' };
	let p = u.params;
	let out = {
		type: 'tuic',
		server: u.host,
		server_port: int(u.port || 443),
		uuid: substr(cred, 0, colon),
		password: substr(cred, colon + 1),
		congestion_control: p.congestion_control || p['congestion-controller'] || null,
		udp_relay_mode: p.udp_relay_mode || p['udp-relay-mode'] || null,
		tls: tls_settings(p, u.host, true)
	};
	return mk_node('tuic', u.name, u.host, u.port || 443, out, []);
}

function parse_anytls(u) {
	if (!length(u.userinfo)) return { ok: false, error: 'anytls missing password' };
	let p = u.params;
	let out = {
		type: 'anytls',
		server: u.host,
		server_port: int(u.port || 443),
		password: url_decode(u.userinfo),
		tls: tls_settings(p, u.host, true)
	};
	return mk_node('anytls', u.name, u.host, u.port || 443, out, []);
}

function parse_socks(u, scheme) {
	let out = {
		type: 'socks',
		server: u.host,
		server_port: int(u.port || 1080),
		version: '5'
	};
	if (length(u.userinfo)) {
		let cred = url_decode(u.userinfo);
		let colon = first_index(cred, ':');
		if (colon >= 0) {
			out.username = substr(cred, 0, colon);
			out.password = substr(cred, colon + 1);
		} else {
			out.username = cred;
		}
	}
	return mk_node('socks', u.name, u.host, u.port || 1080, out, []);
}

function parse_http(u, scheme) {
	let secure = lc2(scheme) == 'https';
	let default_port = secure ? 443 : 8080;
	let out = {
		type: 'http',
		server: u.host,
		server_port: int(u.port || default_port)
	};
	if (length(u.userinfo)) {
		let cred = url_decode(u.userinfo);
		let colon = first_index(cred, ':');
		if (colon >= 0) {
			out.username = substr(cred, 0, colon);
			out.password = substr(cred, colon + 1);
		} else {
			out.username = cred;
		}
	}
	/* https:// 代理是 HTTP over TLS，不加 tls 会被当明文 HTTP 用。 */
	if (secure) out.tls = { enabled: true, server_name: u.host };
	return mk_node('http', u.name, u.host, u.port || default_port, out, []);
}

function parse_link(link) {
	link = trim(link);
	if (!length(link)) return { ok: false, error: 'empty link' };
	let scheme = lc2(substr(link, 0, first_index(link, '://')));
	if (scheme == 'vmess') return parse_vmess(link, parse_url(link) || {});
	let u = parse_url(link);
	if (!u) return { ok: false, error: 'invalid URL' };
	if (!length(u.host)) return { ok: false, error: 'missing host' };
	if (scheme == 'vless') return parse_vless(u);
	if (scheme == 'trojan') return parse_trojan(u);
	if (scheme == 'ss') return parse_ss(link, u);
	if (scheme == 'hysteria2' || scheme == 'hy2') return parse_hysteria2(u);
	if (scheme == 'tuic') return parse_tuic(u);
	if (scheme == 'anytls') return parse_anytls(u);
	if (scheme == 'socks' || scheme == 'socks5') return parse_socks(u, scheme);
	if (scheme == 'http' || scheme == 'https') return parse_http(u, scheme);
	return { ok: false, error: 'unsupported scheme: ' + scheme };
}

/* ---------- Clash YAML proxy mapping ---------- */

function clash_tls(p, server, force) {
	let enabled = p.tls == true || p.tls == 'true' || force;
	if (!enabled) return null;
	let tls = {
		enabled: true,
		server_name: p.servername || p.sni || server,
		insecure: p['skip-cert-verify'] == true || p['skip-cert-verify'] == 'true' ? true : null,
		alpn: p.alpn
	};
	let fp = p['client-fingerprint'];
	if (fp) tls.utls = { enabled: true, fingerprint: fp };
	let reality = p['reality-opts'];
	if (reality && type(reality) == 'object') {
		tls.reality = {
			enabled: true,
			public_key: reality['public-key'],
			short_id: reality['short-id']
		};
	}
	return strip_null(tls);
}

function clash_transport(p, server) {
	let net = lc2(p.network || 'tcp');
	if (net == 'ws') {
		let opts = p['ws-opts'] || {};
		let headers = opts.headers || {};
		return strip_null({ type: 'ws', path: opts.path || '/', headers: { Host: headers.Host || headers.host || server } });
	}
	if (net == 'grpc') {
		let opts = p['grpc-opts'] || {};
		return strip_null({ type: 'grpc', service_name: opts['grpc-service-name'] || '' });
	}
	if (net == 'h2' || net == 'http') {
		let opts = p['h2-opts'] || {};
		return strip_null({ type: 'http', host: opts.host, path: opts.path || '/' });
	}
	return null;
}

/*
 * Clash shadowsocks 插件参数 -> sing-box 插件参数。
 * Clash 写 plugin-opts: { mode, host }，sing-box 的 obfs-local 需要
 * "obfs=<mode>;obfs-host=<host>"；v2ray-plugin 默认 websocket 模式，布尔型
 * tls 在 sing-box 参数里是裸 token。未知插件按原样保留，不丢信息也不崩溃。
 */
function clash_ss_plugin(name, opts) {
	opts = opts != null && type(opts) == 'object' ? opts : {};
	let plugin = lc2(name);
	let parts = [];
	if (plugin == 'obfs') {
		push(parts, 'obfs=' + (opts.mode || 'http'));
		if (length(opts.host || '')) push(parts, 'obfs-host=' + opts.host);
		return { plugin: 'obfs-local', plugin_opts: join(';', parts) };
	}
	if (plugin == 'v2ray-plugin') {
		push(parts, 'mode=' + (opts.mode || 'websocket'));
		if (length(opts.host || '')) push(parts, 'host=' + opts.host);
		if (length(opts.path || '')) push(parts, 'path=' + opts.path);
		if (opts.tls == true || opts.tls == 'true') push(parts, 'tls');
		return { plugin: 'v2ray-plugin', plugin_opts: join(';', parts) };
	}
	for (let k in keys(opts)) {
		if (opts[k] == true) push(parts, k);
		else if (opts[k] != false && opts[k] != null) push(parts, k + '=' + opts[k]);
	}
	return { plugin: name, plugin_opts: join(';', parts) };
}

function clash_to_outbound(p) {
	if (!p || type(p) != 'object') return null;
	let t = lc2(p.type);
	let server = p.server;
	let port = int(p.port);
	let out = { server: server, server_port: port };
	if (t == 'ss' || t == 'shadowsocks') {
		out.type = 'shadowsocks';
		out.method = p.cipher;
		out.password = p.password;
		if (p.plugin) {
			let mapped = clash_ss_plugin(p.plugin, p['plugin-opts']);
			out.plugin = mapped.plugin;
			out.plugin_opts = mapped.plugin_opts;
		}
	} else if (t == 'vmess') {
		out.type = 'vmess';
		out.uuid = p.uuid;
		out.alter_id = int(p.alterId || p.alterid || 0);
		out.security = p.cipher || 'auto';
		out.tls = clash_tls(p, server, false);
		out.transport = clash_transport(p, server);
	} else if (t == 'vless') {
		out.type = 'vless';
		out.uuid = p.uuid;
		out.flow = p.flow;
		out.tls = clash_tls(p, server, false);
		out.transport = clash_transport(p, server);
	} else if (t == 'trojan') {
		out.type = 'trojan';
		out.password = p.password;
		out.tls = clash_tls(p, server, true);
		out.transport = clash_transport(p, server);
	} else if (t == 'hysteria2' || t == 'hy2') {
		out.type = 'hysteria2';
		out.password = p.password || p.auth;
		out.tls = clash_tls(p, server, true);
		if (p.obfs) out.obfs = { type: p.obfs, password: p['obfs-password'] || '' };
		/* mihomo: up/down 是 "100 Mbps" 或数字的带宽，ports 是端口跳跃范围。 */
		let up = positive_int(param_value(p, [ 'up', 'up-mbps', 'up_mbps', 'upmbps' ]));
		if (up > 0) out.up_mbps = up;
		let down = positive_int(param_value(p, [ 'down', 'down-mbps', 'down_mbps', 'downmbps' ]));
		if (down > 0) out.down_mbps = down;
		let ports = port_ranges(param_value(p, [ 'ports', 'port-hopping', 'server_ports', 'server-ports', 'mport' ]));
		if (length(ports)) out.server_ports = ports;
		let hop = hop_interval_text(param_value(p, [ 'hop-interval', 'hop_interval', 'hopinterval' ]));
		if (length(hop)) out.hop_interval = hop;
	} else if (t == 'tuic') {
		out.type = 'tuic';
		out.uuid = p.uuid;
		out.password = p.password;
		out.congestion_control = p['congestion-controller'] || p.congestion_control;
		out.udp_relay_mode = p['udp-relay-mode'] || p.udp_relay_mode;
		out.tls = clash_tls(p, server, true);
	} else if (t == 'anytls') {
		out.type = 'anytls';
		out.password = p.password;
		out.tls = clash_tls(p, server, true);
	} else if (t == 'socks5' || t == 'socks') {
		/*
		 * sing-box 1.14.4's socks outbound has no TLS field (only http does);
		 * emitting tls here would make `sing-box check` fail. Skip the node
		 * instead of silently downgrading an encrypted proxy to plaintext.
		 */
		if (p.tls == true || p.tls == 'true') return null;
		out.type = 'socks';
		out.version = '5';
		out.username = p.username;
		out.password = p.password;
	} else if (t == 'http') {
		out.type = 'http';
		out.username = p.username;
		out.password = p.password;
		out.tls = clash_tls(p, server, false);
	} else {
		return null;
	}
	return strip_null(out);
}

function parse_manual_input(input) {
	input = trim(input);
	if (!length(input)) return { ok: false, error: 'empty input' };
	if (substr(input, 0, 1) == '{') {
		let obj;
		try { obj = json(input); } catch (e) { return { ok: false, error: 'JSON parse failed' }; }
		if (!obj || type(obj) != 'object' || !obj.type || !obj.server)
			return { ok: false, error: 'outbound JSON must contain type and server' };
		let name = obj.tag || obj.name || obj.server;
		delete obj.tag;
		delete obj.name;
		return mk_node(obj.type, name, obj.server, obj.server_port || 0, obj, []);
	}
	return parse_link(input);
}

export { strip_null, url_decode, b64_decode_text, parse_url, parse_link, clash_to_outbound, parse_manual_input };
