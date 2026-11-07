#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright © 2026 technosf <https://github.com/technosf>
# SPDX-License-Identifier: GPL-3.0-or-later
"""
Tuner code-quality metrics for Vala sources (standard library only).

Usage:
    scripts/code_metrics.py [--root src] [--compare OTHER_SRC_DIR] [--top 12] [--json OUT.json]

Measures (see doc/CODE_QUALITY.md for definitions and thresholds):
    size, comment density, cyclomatic complexity (per function), function length,
    parameter count, nesting depth, documentation coverage, duplication,
    maintainability index (approximation), tech-debt markers, and a scan for
    performance / robustness anti-patterns.

The Vala "parser" is a heuristic brace/keyword scanner - good for trends and
hotspots, not a compiler. Numbers are comparable between runs of this script only.
"""
import argparse, bisect, collections, json, math, os, re, sys

CTRL = {'if', 'for', 'foreach', 'while', 'switch', 'catch', 'lock', 'do', 'else', 'try', 'finally', 'using'}
KEYWORDS = set('''abstract as async base break case catch class const construct continue default delegate delete
do else enum ensures errordomain extern false finally for foreach get if in inline interface internal is lock
namespace new null out override owned private protected public ref requires return set sizeof static struct switch
this throw throws true try typeof unowned using value var virtual void volatile weak while yield signal'''.split())
TOKEN_RE = re.compile(r'[A-Za-z_]\w*|\d+(?:\.\d+)?|"[^"]*"|==|!=|<=|>=|&&|\|\||\?\?|=>|\+\+|--|->|[-+*/%=<>!&|^~?:;,.(){}\[\]]')


def strip_source(raw):
    """Return (code, comments, doc_end_lines). code keeps line structure; comments/strings blanked."""
    out, comments, doc_ends = [], [], set()
    i, n, line = 0, len(raw), 1

    def blank(seg):
        return ''.join(c if c == '\n' else ' ' for c in seg)

    while i < n:
        c = raw[i]
        two = raw[i:i + 2]
        if two == '//':
            j = raw.find('\n', i)
            j = n if j < 0 else j
            comments.append((line, raw[i:j]))
            out.append(blank(raw[i:j])); i = j
        elif two == '/*':
            j = raw.find('*/', i + 2)
            j = n if j < 0 else j + 2
            seg = raw[i:j]
            comments.append((line, seg))
            if seg.startswith('/**'):
                doc_ends.add(line + seg.count('\n'))
            out.append(blank(seg)); line += seg.count('\n'); i = j
        elif raw[i:i + 3] == '"""':
            j = raw.find('"""', i + 3)
            j = n if j < 0 else j + 3
            seg = raw[i:j]
            out.append('"' + blank(seg[1:-1]) + '"'); line += seg.count('\n'); i = j
        elif c == '"' or (c == '@' and raw[i + 1:i + 2] == '"'):
            tmpl = c == '@'
            j = i + (2 if tmpl else 1)
            depth = 0
            while j < n:
                d = raw[j]
                if d == '\\' and depth == 0:
                    j += 2; continue
                if tmpl and d == '$' and raw[j + 1:j + 2] == '(':
                    depth += 1; j += 2; continue
                if tmpl and depth > 0:
                    if d == '(':
                        depth += 1
                    elif d == ')':
                        depth -= 1
                    elif d == '"':
                        j += 1
                        while j < n and raw[j] != '"':
                            j += 2 if raw[j] == '\\' else 1
                    j += 1; continue
                if d == '"':
                    break
                j += 1
            seg = raw[i:j + 1]
            out.append(('@"' + blank(seg[2:-1]) if tmpl else '"' + blank(seg[1:-1])) + '"'); line += seg.count('\n'); i = j + 1
        elif c == "'":
            j = i + 1
            while j < n and raw[j] != "'":
                j += 2 if raw[j] == '\\' else 1
            seg = raw[i:j + 1]
            out.append("'x'" + blank(seg[3:])); i = j + 1
        else:
            out.append(c)
            if c == '\n':
                line += 1
            i += 1
    return ''.join(out), comments, doc_ends


FUNC_RE = re.compile(r'(?P<mods>(?:[\w\.<>\?\[\],]+\s+)*?)(?P<name>[A-Za-z_]\w*)\s*\((?P<params>.*)\)\s*(?:throws\s+[\w\.,\s]+)?$', re.S)
CONT_RE = re.compile(r'\b(class|interface|struct|enum|namespace|errordomain)\s+([\w\.]+)')
ACC_RE = re.compile(r'(?:^|\s)(get|set|construct)\s*$')
ATTR_RE = re.compile(r'^(\s*\[[^\]]*\]\s*)+')
CC_RES = [re.compile(x) for x in (r'\bif\b', r'\bfor\b', r'\bforeach\b', r'\bwhile\b', r'\bcase\b', r'\bcatch\b',
                                   r'&&', r'\|\|', r'\?\?', r'(?<=\s)\?(?=\s)')]


def count_params(p):
    p = p.strip()
    if not p:
        return 0
    depth, cnt = 0, 1
    for ch in p:
        if ch in '<(':
            depth += 1
        elif ch in '>)':
            depth -= 1
        elif ch == ',' and depth == 0:
            cnt += 1
    return cnt


def parse_file(path, raw):
    code, comments, doc_ends = strip_source(raw)
    line_starts = [0] + [m.end() for m in re.finditer(r'\n', code)]
    line_of = lambda idx: bisect.bisect_right(line_starts, idx)
    raw_lines = raw.split('\n')
    funcs, containers = [], []
    stack = []
    hdr = 0
    in_func = 0
    fdepth = 0
    for i, ch in enumerate(code):
        if ch == '{':
            header = code[hdr:i]
            h = ATTR_RE.sub('', header).strip()
            hstart_idx = hdr + (len(header) - len(header.lstrip()))
            kind = 'block'
            name = params = ''
            if in_func == 0:
                m_acc = ACC_RE.search(h)
                m_cont = CONT_RE.search(h)
                if m_cont and '(' not in h.split(m_cont.group(1))[0]:
                    kind = 'container'
                    containers.append({'name': m_cont.group(2), 'kind': m_cont.group(1), 'line': line_of(hstart_idx), 'header': h})
                elif m_acc:
                    kind = 'func'; name = m_acc.group(1)
                elif '(' in h and h.split()[0] not in CTRL and not h.startswith('delegate'):
                    m = FUNC_RE.match(h)
                    if m:
                        kind = 'func'; name = m.group('name'); params = m.group('params')
                elif h and re.match(r'^[\w\.<>\?\[\], ]+$', h):
                    kind = 'prop'
            if kind == 'func':
                in_func = 1; fdepth = 0
                stack.append(('func', name, {'start_idx': hstart_idx, 'body_idx': i + 1, 'params': params, 'header': h, 'maxd': 0}))
            else:
                if in_func:
                    fdepth += 1
                    for k in range(len(stack) - 1, -1, -1):
                        if stack[k][0] == 'func':
                            stack[k][2]['maxd'] = max(stack[k][2]['maxd'], fdepth); break
                stack.append((kind, '', {}))
            hdr = i + 1
        elif ch == '}':
            if stack:
                kind, name, info = stack.pop()
                if kind == 'func':
                    body = code[info['body_idx']:i]
                    sl, el = line_of(info['start_idx']), line_of(i)
                    sloc = sum(1 for l in code[info['start_idx']:i + 1].split('\n') if l.strip())
                    cc = 1 + sum(len(r.findall(body)) for r in CC_RES)
                    mods = info['header'].split('(')[0].split()
                    public = any(x in ('public', 'internal', 'protected') for x in mods)
                    j = sl - 2
                    while j >= 0 and not raw_lines[j].strip():
                        j -= 1
                    if name in ('get', 'set') and cc == 1 and sloc <= 3:
                        in_func = 0; hdr = i + 1
                        continue      # trivial accessor - not a function worth measuring
                    funcs.append({'name': name, 'line': sl, 'end': el, 'sloc': sloc, 'cc': cc,
                                  'params': count_params(info['params']), 'depth': info['maxd'],
                                  'public': public, 'documented': (j + 1) in doc_ends})
                    in_func = 0
                elif in_func:
                    fdepth -= 1
            hdr = i + 1
        elif ch == ';':
            hdr = i + 1
    for c in containers:
        j = c['line'] - 2
        while j >= 0 and not raw_lines[j].strip():
            j -= 1
        c['documented'] = (j + 1) in doc_ends
        c['public'] = bool(re.search(r'\b(public|internal)\b', c['header']))
    return code, comments, doc_ends, funcs, containers


TODO_RE = re.compile(r'\b(TODO|FIXME|HACK|XXX)\b|@todo', re.I)
CODEISH_RE = re.compile(r'^\s*//+\s*(?:[\w\.]+\s*(?:=|\+=|\()[^/]*[;{]\s*$|if\s*\(.*[{;]\s*$|return\b.*;\s*$|var\s+\w+.*;\s*$|}\s*$|[\w\.]+\(.*\);\s*$)')

ANTI = collections.OrderedDict([
    ('sync_http_get', (re.compile(r'HttpClient\.(GET|HEAD)\('), 'Blocking HTTP on the calling (usually UI) thread')),
    ('eager_debug', (re.compile(r'\bdebug\s*\(\s*@"'), 'debug(@"...") builds its string even when debug logging is off')),
    ('timers', (re.compile(r'\b(Timeout\.add\w*|Idle\.add\w*)\s*\('), 'Timers / idle callbacks (check each is removed)')),
    ('connects', (re.compile(r'\.connect\s*\('), 'Signal connections')),
    ('disconnects', (re.compile(r'\.disconnect\s*\('), 'Signal disconnections')),
    ('empty_catch', (re.compile(r'catch\s*\([^)]*\)\s*\{\s*\}'), 'Empty catch blocks (swallowed errors)')),
    ('app_global', (re.compile(r'\bapp\s*\(\s*\)'), 'Global app() accessor calls (hidden coupling)')),
    ('to_array', (re.compile(r'\.to_array\s*\(\s*\)'), 'Collection copies via to_array()')),
    ('sleep', (re.compile(r'Thread\.(u?sleep)\s*\('), 'Thread sleeps')),
])


def halstead_mi(code, total_cc, sloc):
    """Visual Studio style maintainability index with a token-based Halstead volume (0-100)."""
    toks = TOKEN_RE.findall(code)
    if not toks or sloc == 0:
        return 100.0
    ops, opnds = collections.Counter(), collections.Counter()
    for t in toks:
        if t in KEYWORDS or not (t[0].isalnum() or t[0] in '_"'):
            ops[t] += 1
        else:
            opnds[t] += 1
    n = len(ops) + len(opnds)
    N = sum(ops.values()) + sum(opnds.values())
    v = N * math.log2(n) if n > 1 else 1
    mi = (171 - 5.2 * math.log(max(v, 1)) - 0.23 * total_cc - 16.2 * math.log(max(sloc, 1))) * 100 / 171
    return max(0.0, mi)


def analyse(root, exclude=()):
    files = {}
    sig_lines = {}
    anti_sites = collections.defaultdict(list)
    for dp, _, fns in os.walk(root):
        for fn in sorted(fns):
            if not fn.endswith('.vala'):
                continue
            path = os.path.join(dp, fn)
            rel = os.path.relpath(path, root)
            if any(x in rel for x in exclude):
                continue
            raw = open(path, encoding='utf-8', errors='replace').read()
            code, comments, doc_ends, funcs, conts = parse_file(path, raw)
            lines = raw.split('\n')
            blank = sum(1 for l in lines if not l.strip())
            sloc = sum(1 for l in code.split('\n') if l.strip())
            comment_lines = sum(c[1].count('\n') + 1 for c in comments)
            todos = []
            for cl, ctext in comments:
                for off, ctl in enumerate(ctext.split('\n')):
                    if TODO_RE.search(ctl):
                        todos.append((cl + off, ctl.strip()[:90]))
            coc = sum(1 for c in comments if c[1].startswith('//') and CODEISH_RE.match(c[1]))
            total_cc = sum(f['cc'] for f in funcs) or 1
            sig = [re.sub(r'\s+', ' ', l.strip()) for l in code.split('\n')]
            sig = [(ix + 1, l) for ix, l in enumerate(sig) if len(l) >= 8 and not re.fullmatch(r'[\W]*', l)]
            sig_lines[rel] = sig
            anti = {}
            for key, (rx, _) in ANTI.items():
                hits = [code.count('\n', 0, m.start()) + 1 for m in rx.finditer(code)]
                if key == 'eager_debug':     # a debug_enabled() guard on the previous line makes it cheap
                    cl = code.split('\n')
                    hits = [h for h in hits if 'debug_enabled' not in cl[h - 2]]
                anti[key] = len(hits)
                for h in hits:
                    anti_sites[key].append((rel, h))
            files[rel] = {'sloc': sloc, 'blank': blank, 'comment_lines': comment_lines, 'funcs': funcs, 'conts': conts,
                          'todos': todos, 'commented_code': coc, 'mi': halstead_mi(code, total_cc, sloc),
                          'usings': len(re.findall(r'^\s*using\s', code, re.M)), 'anti': anti}
    W = 6    # duplication: windows of 6 consecutive significant lines
    seen = collections.defaultdict(list)
    for rel, sig in sig_lines.items():
        for k in range(len(sig) - W + 1):
            win = tuple(l for _, l in sig[k:k + W])
            if len(set(win)) <= 3:      # repeated lines / table rows are data, not copy-paste logic
                continue
            seen[win].append((rel, k))
    dup_cover = {rel: set() for rel in sig_lines}
    pairs = collections.Counter()
    for key, occ in seen.items():
        if len(occ) > 1:
            if len({r for r, _ in occ}) == 1 and max(k for _, k in occ) - min(k for _, k in occ) < W:
                continue                # overlapping with itself
            for rel, k in occ:
                dup_cover[rel].update(range(k, k + W))
            for a in range(len(occ)):
                for b in range(a + 1, len(occ)):
                    pairs[tuple(sorted((occ[a][0], occ[b][0])))] += 1
    for rel in files:
        files[rel]['sig_lines'] = len(sig_lines[rel])
        files[rel]['dup_lines'] = len(dup_cover[rel])
    return files, pairs, anti_sites


def percentile(vals, p):
    if not vals:
        return 0
    s = sorted(vals)
    return s[min(len(s) - 1, int(round(p / 100 * (len(s) - 1))))]


def summarise(files):
    funcs = [dict(f, file=r) for r, d in files.items() for f in d['funcs']]
    sloc = sum(d['sloc'] for d in files.values())
    pub = [f for f in funcs if f['public']]
    conts = [c for d in files.values() for c in d['conts'] if c['public'] and c['kind'] != 'namespace']
    documented = sum(f['documented'] for f in pub) + sum(c['documented'] for c in conts)
    doc_total = len(pub) + len(conts)
    ccs = [f['cc'] for f in funcs]
    sig = sum(d['sig_lines'] for d in files.values())
    dup = sum(d['dup_lines'] for d in files.values())
    mi_w = sum(d['mi'] * d['sloc'] for d in files.values()) / max(sloc, 1)
    anti = collections.Counter()
    for d in files.values():
        anti.update(d['anti'])
    s = collections.OrderedDict()
    s['Files'] = len(files)
    s['Source lines (SLOC)'] = sloc
    s['Comment lines'] = sum(d['comment_lines'] for d in files.values())
    s['Comment density %'] = round(100 * s['Comment lines'] / max(sloc + s['Comment lines'], 1), 1)
    s['Functions / methods'] = len(funcs)
    s['Average CC'] = round(sum(ccs) / max(len(ccs), 1), 2)
    s['Median CC'] = percentile(ccs, 50)
    s['90th percentile CC'] = percentile(ccs, 90)
    s['Max CC'] = max(ccs) if ccs else 0
    s['Functions CC > 10'] = sum(c > 10 for c in ccs)
    s['Functions CC > 20'] = sum(c > 20 for c in ccs)
    s['Functions > 50 SLOC'] = sum(f['sloc'] > 50 for f in funcs)
    s['Functions > 100 SLOC'] = sum(f['sloc'] > 100 for f in funcs)
    s['Functions > 5 params'] = sum(f['params'] > 5 for f in funcs)
    s['Functions nesting > 4'] = sum(f['depth'] > 4 for f in funcs)
    s['Files > 500 SLOC'] = sum(d['sloc'] > 500 for d in files.values())
    s['Files > 1000 SLOC'] = sum(d['sloc'] > 1000 for d in files.values())
    s['Public API documented %'] = round(100 * documented / max(doc_total, 1), 1)
    s['Duplicated lines %'] = round(100 * dup / max(sig, 1), 1)
    s['Maintainability index (SLOC-weighted)'] = round(mi_w, 1)
    s['Files with MI < 20'] = sum(d['mi'] < 20 for d in files.values())
    s['TODO/FIXME/HACK markers'] = sum(len(d['todos']) for d in files.values())
    s['Commented-out code lines'] = sum(d['commented_code'] for d in files.values())
    s['Empty catch blocks'] = anti['empty_catch']
    s['Blocking HTTP call sites'] = anti['sync_http_get']
    s['Eager debug(@"...") calls'] = anti['eager_debug']
    s['Timer / idle registrations'] = anti['timers']
    s['Signal connect : disconnect'] = f"{anti['connects']} : {anti['disconnects']}"
    s['Global app() calls'] = anti['app_global']
    return s


def md_table(rows, header):
    out = ['| ' + ' | '.join(header) + ' |', '|' + '|'.join('---' for _ in header) + '|']
    out += ['| ' + ' | '.join(str(c) for c in r) + ' |' for r in rows]
    return '\n'.join(out)


# Always left out of the metrics: not part of the shipped app's logic.
#   Widgets/granite             vendored code
#   Services/ScreenshotMode     developer-only tool for taking store screenshots
DEFAULT_EXCLUDE = ('Widgets/granite', 'Services/ScreenshotMode')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default='src')
    ap.add_argument('--compare', help='another source dir (e.g. a release checkout) to show side by side')
    ap.add_argument('--top', type=int, default=12)
    ap.add_argument('--exclude', action='append', default=[], help='also skip files whose relative path contains this (always skipped: ' + ', '.join(DEFAULT_EXCLUDE) + ')')
    ap.add_argument('--json')
    a = ap.parse_args()
    a.exclude = list(DEFAULT_EXCLUDE) + a.exclude

    files, pairs, sites = analyse(a.root, a.exclude)
    summ = summarise(files)
    base = summarise(analyse(a.compare, a.exclude)[0]) if a.compare else None

    print('## Summary\n')
    if base:
        rows = []
        for k, v in summ.items():
            b = base[k]
            try:
                d = f'{round(float(str(v)) - float(str(b)), 2):+g}'
            except ValueError:
                d = ''
            rows.append((k, v, b, d))
        print(md_table(rows, ['Metric', 'Current', 'Baseline', 'Change']))
    else:
        print(md_table(list(summ.items()), ['Metric', 'Value']))

    funcs = [dict(f, file=r) for r, d in files.items() for f in d['funcs']]
    print('\n## Highest cyclomatic complexity\n')
    print(md_table([(f"`{f['file']}:{f['line']}`", f['name'], f['cc'], f['sloc'], f['params'], f['depth'])
                    for f in sorted(funcs, key=lambda f: -f['cc'])[:a.top]], ['Location', 'Function', 'CC', 'SLOC', 'Params', 'Max nesting']))
    print('\n## Longest functions\n')
    print(md_table([(f"`{f['file']}:{f['line']}`", f['name'], f['sloc'], f['cc']) for f in sorted(funcs, key=lambda f: -f['sloc'])[:a.top]],
                   ['Location', 'Function', 'SLOC', 'CC']))
    print('\n## Largest files\n')
    big = sorted(files.items(), key=lambda kv: -kv[1]['sloc'])[:a.top]
    print(md_table([(f'`{r}`', d['sloc'], len(d['funcs']), round(sum(f['cc'] for f in d['funcs']) / max(len(d['funcs']), 1), 1), round(d['mi'], 1)) for r, d in big],
                   ['File', 'SLOC', 'Functions', 'Avg CC', 'MI']))
    print('\n## Lowest maintainability index\n')
    print(md_table([(f'`{r}`', round(d['mi'], 1), d['sloc'], sum(f['cc'] for f in d['funcs'])) for r, d in sorted(files.items(), key=lambda kv: kv[1]['mi'])[:a.top]],
                   ['File', 'MI', 'SLOC', 'Total CC']))
    print('\n## Duplication (6-line windows shared between files)\n')
    print(md_table([(f'`{x}`', f'`{y}`', n) for (x, y), n in pairs.most_common(a.top)], ['File A', 'File B', 'Shared windows']))
    print('\n## Tech-debt markers\n')
    rows = [(f'`{r}:{ln}`', t.replace('|', '/')) for r, d in files.items() for ln, t in d['todos']]
    print(md_table(rows[:40], ['Location', 'Marker']) if rows else 'None')
    print('\nCommented-out code by file: ' + ', '.join(f'`{r}` {d["commented_code"]}' for r, d in sorted(files.items(), key=lambda kv: -kv[1]['commented_code'])[:8] if d['commented_code']))
    print('\n## Anti-pattern scan\n')
    rows = []
    for key, (_, desc) in ANTI.items():
        cnt = collections.Counter(r for r, _ in sites[key])
        rows.append((key, desc, sum(cnt.values()), ', '.join(f'`{r}` {n}' for r, n in cnt.most_common(4))))
    print(md_table(rows, ['Check', 'Meaning', 'Count', 'Top files']))
    print('\nBlocking HTTP call sites: ' + ', '.join(f'`{r}:{l}`' for r, l in sites['sync_http_get']))
    if a.json:
        json.dump({'summary': summ, 'baseline': base}, open(a.json, 'w'), indent=2)


if __name__ == '__main__':
    main()
