'use strict';

import { trim, read_json, write_json, mkdir_p, run_capture, sh_quote, PATH, VERSION, now_string } from 'sbx_common';

const API_BASE = 'https://api.github.com/repos/';

function mirror_url(url, mirror) {
	if (!length(mirror || '')) return url;
	let prefix = substr(mirror, -1) == '/' ? mirror : mirror + '/';
	return prefix + url;
}

/* GitHub API release list -> tag list (newest first, drafts/prereleases skipped). */
function parse_tags(raw, limit) {
	let data = null;
	try { data = json(raw); } catch (e) { data = null; }
	if (type(data) != 'array') return [];
	let max = int(limit || 10);
	if (max < 1) max = 10;
	let out = [];
	for (let rel in data) {
		if (!rel || type(rel) != 'object') continue;
		if (rel.draft == true || rel.prerelease == true) continue;
		let tag = trim(rel.tag_name || '');
		if (!length(tag)) continue;
		if (index(out, tag) >= 0) continue;
		push(out, tag);
		if (length(out) >= max) break;
	}
	return out;
}

/* Releases page HTML -> tag list; used when the API is unreachable. */
function parse_release_page(html, limit) {
	let max = int(limit || 10);
	if (max < 1) max = 10;
	let out = [];
	let rest = html == null ? '' : html;
	while (length(out) < max) {
		let m = match(rest, /releases\/tag\/([^"'\s?&#]+)/);
		if (!m) break;
		let tag = trim(m[1]);
		if (length(tag) && index(out, tag) < 0) push(out, tag);
		let pos = index(rest, m[0]);
		rest = substr(rest, pos + length(m[0]));
		if (!length(rest)) break;
	}
	return out;
}

function list_tags(repo, mirror, limit) {
	let max = int(limit || 10);
	if (max < 1) max = 10;
	let api = API_BASE + repo + '/releases?per_page=' + max;
	let page = 'https://github.com/' + repo + '/releases';
	let urls = [];
	if (length(mirror || '')) {
		push(urls, mirror_url(api, mirror));
		push(urls, mirror_url(page, mirror));
	}
	push(urls, api);
	push(urls, page);
	for (let url in urls) {
		let r = run_capture('curl -fsSL --connect-timeout 6 --max-time 12' +
			' -H ' + sh_quote('Accept: application/vnd.github+json') +
			' -A ' + sh_quote('singbox-lite/' + VERSION) +
			' ' + sh_quote(url));
		if (!r.ok) continue;
		let tags = parse_tags(r.out, max);
		if (!length(tags)) tags = parse_release_page(r.out, max);
		if (length(tags)) return { ok: true, tags: tags };
	}
	return { ok: false, tags: [], error: '无法获取版本列表（GitHub API 不可用，请稍后重试）' };
}

function latest_tag(repo, mirror, limit) {
	let l = list_tags(repo, mirror, limit || 5);
	if (l.ok && length(l.tags)) return { ok: true, tag: l.tags[0], tags: l.tags };
	let url = 'https://github.com/' + repo + '/releases/latest';
	let r = run_capture("curl -sIL --connect-timeout 10 --max-time 30 -o /dev/null -w '%{url_effective}' " + sh_quote(url));
	if (!r.ok) return { ok: false, error: '无法访问 GitHub releases' };
	let eff = trim(r.out);
	let pos = rindex(eff, '/tag/');
	if (pos == null || pos < 0) return { ok: false, error: '无法解析最新版本' };
	return { ok: true, tag: substr(eff, pos + 5) };
}

function cache_file() {
	return PATH.releases_cache;
}

function cache_read() {
	let c = read_json(cache_file(), null);
	if (!c || type(c) != 'object') return { core: [], plugin: [], checked_at: '' };
	if (type(c.core) != 'array') c.core = [];
	if (type(c.plugin) != 'array') c.plugin = [];
	return c;
}

function cache_write(data) {
	mkdir_p(PATH.run_dir);
	let out = { core: [], plugin: [], checked_at: now_string() };
	if (data && type(data) == 'object')
		for (let k in keys(data)) out[k] = data[k];
	return write_json(cache_file(), out, 384);
}

export { API_BASE, mirror_url, parse_tags, parse_release_page, list_tags, latest_tag, cache_file, cache_read, cache_write };