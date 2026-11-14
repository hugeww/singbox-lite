'use strict';

import { trim, split_lines, split_csv, file_exists, read_text, write_text, mkdir_p, shell_http_get, PATH, log_app, run_capture, sh_quote } from 'sbx_common';
import { unlink, rename, stat } from 'fs';

const BUILTIN = {
	builtin_cn_ai: {
		name: '国内 AI',
		order: 100,
		default_target: 'direct',
		inline_domains: [
			'deepseek.com', 'chat.deepseek.com', 'moonshot.cn', 'kimi.com',
			'kimi.moonshot.cn', 'tongyi.aliyun.com', 'qwen.ai', 'qwenlm.ai',
			'doubao.com', 'yiyan.baidu.com', 'wenxin.baidu.com',
			'hunyuan.tencent.com', 'zhipuai.cn', 'bigmodel.cn',
			'baichuan-ai.com', 'minimax.com', 'minimaxi.com',
			'sensetime.com', 'sensenova.cn', 'stepfun.com'
		]
	},
	builtin_cn: {
		name: '国内',
		order: 110,
		default_target: 'direct',
		files: [ 'geosite-cn.srs', 'geoip-cn.srs' ]
	},
	builtin_ai: {
		name: '国外 AI',
		order: 120,
		default_target: 'default',
		files: [ 'geosite-category-ai-!cn.srs', 'geosite-openai.srs', 'geosite-anthropic.srs', 'geosite-google-gemini.srs' ]
	},
	builtin_streaming: {
		name: '流媒体',
		order: 130,
		default_target: 'default',
		files: [ 'geosite-youtube.srs', 'geosite-tiktok.srs', 'geosite-netflix.srs', 'geosite-disney.srs', 'geosite-primevideo.srs', 'geosite-hbo.srs', 'geosite-spotify.srs' ]
	},
	builtin_social: {
		name: '社交',
		order: 140,
		default_target: 'default',
		files: [ 'geosite-telegram.srs', 'geosite-twitter.srs', 'geosite-whatsapp.srs', 'geosite-instagram.srs', 'geosite-facebook.srs' ]
	},
	builtin_dev: {
		name: '开发',
		order: 150,
		default_target: 'default',
		files: [ 'geosite-category-dev.srs', 'geosite-github.srs' ]
	}
};

function builtin_section(cfg, source) {
	for (let rs in cfg.rulesets)
		if (rs.kind == 'builtin' && rs.source == source)
			return rs;
	return null;
}

function file_path(name) {
	let updated = PATH.rulesets_dir + '/' + name;
	if (file_exists(updated)) return updated;
	return PATH.builtin_rulesets_dir + '/' + name;
}

function slug(s) {
	s = lc(trim(s == null ? '' : s));
	s = replace(s, /[^a-z0-9_-]+/g, '_');
	s = replace(s, /^_+|_+$/g, '');
	if (!length(s)) s = 'x';
	return substr(s, 0, 32);
}

function rule_set_tag(id, index) {
	let s = slug(id);
	if (substr(s, 0, 3) != 'rs_') s = 'rs_' + s;
	return s + '_' + int(index);
}

function parse_inline(domains) {
	let result = { domain_suffix: [], ip_cidr: [], port: [] };
	for (let line in split_lines(domains || '')) {
		let v = trim(line);
		if (!length(v) || substr(v, 0, 1) == '#') continue;
		if (substr(v, 0, 8) == 'port:') { push(result.port, substr(v, 5)); continue; }
		if (substr(v, 0, 5) == 'ip:') { push(result.ip_cidr, substr(v, 3)); continue; }
		if (substr(v, 0, 7) == 'domain:') { push(result.domain_suffix, substr(v, 7)); continue; }
		if (substr(v, 0, 7) == 'suffix:') { push(result.domain_suffix, substr(v, 7)); continue; }
		if (match(v, /^[0-9a-fA-F:.]+\/[0-9]+$/)) { push(result.ip_cidr, v); continue; }
		push(result.domain_suffix, v);
	}
	return result;
}

function resolve_rulesets(cfg) {
	let result = { rules: [], errors: [] };
	let custom = [];
	for (let rs in cfg.rulesets) {
		if (rs.kind == 'builtin') continue;
		if (rs.enabled == '0') continue;
		push(custom, rs);
	}
	sort(custom, (a, b) => int(a.order || 10) - int(b.order || 10));

	for (let rs in custom) {
		let entry = {
			id: rs['.name'],
			kind: 'custom',
			name: rs.name || rs['.name'],
			target: rs.target || 'default',
			files: [],
			inline: { domain_suffix: [], ip_cidr: [], port: [] },
			order: int(rs.order || 10)
		};
		let type_ = rs.type || 'inline';
		if (type_ == 'inline') {
			entry.inline = parse_inline(rs.domains || '');
			if (!length(entry.inline.domain_suffix) && !length(entry.inline.ip_cidr) && !length(entry.inline.port)) {
				push(result.errors, sprintf('自定义规则集 %s 内容为空', entry.name));
				continue;
			}
		} else {
			let path = rs.path || '';
			if (type_ == 'remote')
				path = PATH.rulesets_dir + '/' + rs['.name'] + '.srs';
			if (!length(path) || !file_exists(path)) {
				push(result.errors, sprintf('规则集 %s 的文件不存在：%s', entry.name, path));
				continue;
			}
			push(entry.files, { tag: rule_set_tag(entry.id, 0), path: path });
		}
		push(result.rules, entry);
	}

	for (let source in [ 'builtin_cn_ai', 'builtin_cn', 'builtin_ai', 'builtin_streaming', 'builtin_social', 'builtin_dev' ]) {
		let def = BUILTIN[source];
		let sec = builtin_section(cfg, source);
		if (sec && sec.enabled == '0') continue;
		let entry = {
			id: sec ? sec['.name'] : 'rs_' + source,
			kind: 'builtin',
			name: def.name,
			target: (sec && sec.target) || def.default_target,
			files: [],
			inline: { domain_suffix: [], ip_cidr: [], port: [] },
			order: def.order
		};
		if (def.files) {
			let idx = 0;
			for (let f in def.files) {
				let path = file_path(f);
				if (!file_exists(path)) {
					push(result.errors, sprintf('内置规则集 %s 缺少文件：%s', def.name, f));
					continue;
				}
				push(entry.files, { tag: rule_set_tag(entry.id, idx++), path: path });
			}
		}
		if (def.inline_domains)
			entry.inline.domain_suffix = def.inline_domains;
		push(result.rules, entry);
	}
	return result;
}

function update_ruleset(cfg, id) {
	let rs = null;
	for (let item in cfg.rulesets)
		if (item['.name'] == id) { rs = item; break; }
	if (!rs) return { ok: false, error: '规则集不存在' };
	if (rs.kind == 'builtin') return { ok: false, error: '内置规则集请使用内置更新' };
	if ((rs.type || 'inline') != 'remote') return { ok: false, error: '只有远程规则集需要更新' };
	if (!length(rs.url || '')) return { ok: false, error: '缺少远程 URL' };
	mkdir_p(PATH.rulesets_dir);
	let out = PATH.rulesets_dir + '/.' + id + '.srs.tmp';
	let hdr = PATH.run_dir + '/' + id + '.hdr';
	let r = shell_http_get(rs.url, out, hdr, 'sing-box/1.14', 120);
	if (!r.ok || trim(r.out) != '200') {
		try { unlink(out); } catch (e) {}
		return { ok: false, error: '下载失败：' + trim(r.out) };
	}
	let st = stat(out);
	if (!st || !st.size) {
		try { unlink(out); } catch (e) {}
		return { ok: false, error: '下载内容为空' };
	}
	if (rename(out, PATH.rulesets_dir + '/' + id + '.srs') !== true)
		return { ok: false, error: '保存规则集失败' };
	return { ok: true, size: st.size };
}

function update_builtin_rulesets(mirror) {
	let prefix = length(mirror || '') ? (substr(mirror, -1) == '/' ? mirror : mirror + '/') : '';
	let files = [];
	for (let source in BUILTIN)
		for (let f in (BUILTIN[source].files || []))
			push(files, f);
	mkdir_p(PATH.rulesets_dir);
	let updated = 0, failed = [];
	for (let f in files) {
		let repo = substr(f, 0, 5) == 'geoip' ? 'sing-geoip' : 'sing-geosite';
		let url = prefix + 'https://raw.githubusercontent.com/SagerNet/' + repo + '/rule-set/' + f;
		let out = PATH.rulesets_dir + '/' + f;
		let tmp = out + '.tmp';
		let r = shell_http_get(url, tmp, PATH.run_dir + '/ruleset.hdr', 'sing-box/1.14', 120);
		let st = stat(tmp);
		if (!r.ok || trim(r.out) != '200' || !st || !st.size) {
			try { unlink(tmp); } catch (e) {}
			push(failed, f);
			continue;
		}
		try { rename(tmp, out); updated++; } catch (e) { push(failed, f); }
	}
	return { ok: length(failed) == 0, updated: updated, failed: failed };
}

function ruleset_files_for_validation(cfg) {
	let result = resolve_rulesets(cfg);
	let files = [];
	for (let rule in result.rules)
		for (let f in rule.files)
			push(files, f.path);
	return files;
}

export { BUILTIN, rule_set_tag, resolve_rulesets, update_ruleset, update_builtin_rulesets, ruleset_files_for_validation };
