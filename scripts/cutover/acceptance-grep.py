#!/usr/bin/env python3
"""Acceptance grep for the Sylveste public-hygiene scrub.

Usage: acceptance-grep.py <checkout> <public-repo-patterns.tsv>
                          [--json OUT] [--defer FILE [--ceiling FILE]]

Applies every rule in the pre-push guard's TSV to the committed HEAD tree of
<checkout>: text rules to blob contents, path rules to tracked paths. Contents
are read from git objects (`git cat-file --batch`), not the working tree, so a
missing or edited working file cannot hide a hit. Honours the guard's escapes:
inline `hygiene:allow(rule-id)` on the same line and the committed
`.public-hygiene-allow` (`rule-id path-glob -- reason`). Prints counts only,
never matched text.

--defer FILE scopes an intermediate PR: each line is `path-prefix -- reason`.
Hits under a deferred prefix are counted separately as `deferred`.
--ceiling FILE caps the deferred hits. It is either {"files": N, "rules": {rule: max}}
or this script's own --json report from the PR's base commit run with the same
--defer file, so a PR cannot add hits under a deferred prefix:
any count above its ceiling, or a rule absent from the ceiling, fails the run.
The final acceptance run passes neither option.

Exit 0 = zero unallowed hits and deferred within ceiling; 1 = hits or ceiling
exceeded; 3 = the checkout could not be enumerated or read completely
(not a git work tree, dirty tracked files, git failure, unreadable blob, bad
option file, unknown rule kind, malformed rule or allow entry). Exit 3 never
reports a result.

Schemas are strict, because a skipped rule or a loose escape is a false zero:
  rules TSV   exactly 4 tab-separated columns per non-comment line; rule-id
              [a-z0-9-]+ and unique; scope exactly `text` or `path`; regex
              compiles; description non-empty.
  allow file  `rule-id path-glob -- reason`, reason non-empty, rule-id a
              loaded rule. The guard ignores reasonless entries, so this
              checker refuses them rather than honouring them.
  ceiling     {"files": int>=0, "rules": {known-rule-id: int>=0}} or a report
              of this script with integer counts.
  inline      `hygiene:allow(rule-id[,rule-id])` on the hit's line.
"""
import fnmatch, json, re, subprocess, sys
from collections import Counter, defaultdict
from typing import NoReturn

RULE_ID = re.compile(r'[a-z0-9-]+')
INLINE = re.compile(r'hygiene:allow\(([^)]*)\)')


def fail(msg) -> NoReturn:
    print(json.dumps({'error': msg}))
    sys.exit(3)


# Any unexpected exception is "could not read", never a result.
sys.excepthook = lambda t, v, tb: fail(f'internal error: {t.__name__}')


def git(*args, **kw):
    r = subprocess.run(['git', '-C', repo, *args], capture_output=True, **kw)
    if r.returncode != 0:
        fail(f'git {args[0]} failed (rc {r.returncode})')
    return r.stdout


def opt(name):
    if name not in sys.argv:
        return None
    i = sys.argv.index(name)
    if i + 1 >= len(sys.argv):
        fail(f'{name} needs a value')
    return sys.argv[i + 1]


if len(sys.argv) < 3:
    fail('usage: acceptance-grep.py <checkout> <tsv> [--json OUT] [--defer FILE [--ceiling FILE]]')
repo, tsv = sys.argv[1], sys.argv[2]
out, defer_file, ceiling_file = opt('--json'), opt('--defer'), opt('--ceiling')
if ceiling_file and not defer_file:
    fail('--ceiling requires --defer')

try:
    defer = []
    if defer_file:
        for line in open(defer_file):
            line = line.split('--')[0].strip()
            if line and not line.startswith('#'):
                defer.append(line)
        if not defer:
            fail('--defer file has no prefixes')
    ceiling = json.load(open(ceiling_file)) if ceiling_file else None
    rules = []
    for n, line in enumerate(open(tsv), 1):
        if not line.strip() or line.startswith('#'):
            continue
        f = line.rstrip('\n').split('\t')
        if len(f) != 4:
            fail(f'rules line {n}: {len(f)} columns, want 4')
        rid, kind, rx, desc = f
        if not RULE_ID.fullmatch(rid) or rid in {r for r, _, _ in rules}:
            fail(f'rules line {n}: bad or duplicate rule id')
        if kind not in ('text', 'path'):
            fail(f'rules line {n}: unknown scope')
        if not rx or not desc.strip():
            fail(f'rules line {n}: empty regex or description')
        rules.append((rid, kind, re.compile(rx)))
except (OSError, ValueError, re.error) as e:
    fail(f'cannot load option files: {type(e).__name__}')
if not rules:
    fail('no rules loaded')
rule_ids = {r for r, _, _ in rules}


def count(v):
    return isinstance(v, int) and not isinstance(v, bool) and v >= 0


if ceiling is not None:
    if not isinstance(ceiling, dict):
        fail('ceiling: not an object')
    if 'deferred' in ceiling:   # a --json report from the PR's base commit
        ceiling = {'files': ceiling.get('files_with_deferred_hits'), 'rules': ceiling['deferred']}
    caps = ceiling.get('rules')
    if not count(ceiling.get('files')) or not isinstance(caps, dict) \
            or not all(k in rule_ids and count(v) for k, v in caps.items()):
        fail('ceiling: bad schema or unknown rule id')

if git('rev-parse', '--is-inside-work-tree', text=True).strip() != 'true':
    fail('not a git work tree')
if git('status', '--porcelain', '--untracked-files=no', text=True).strip():
    fail('tracked files are modified; acceptance runs on a clean checkout')
head = git('rev-parse', 'HEAD', text=True).strip()

# mode type sha\tpath, NUL-separated; gitlinks (commit) are reported, not read.
entries, gitlinks = [], []
for rec in filter(None, git('ls-tree', '-r', '-z', '--full-tree', 'HEAD').decode().split('\0')):
    meta, tab, path = rec.partition('\t')
    if not tab or len(meta.split()) != 3:
        fail('unparseable ls-tree record')
    mode, typ, sha = meta.split()
    (gitlinks if typ == 'commit' else entries).append((path, sha))
if not entries:
    fail('HEAD tree is empty')

blobs = {}
proc = subprocess.run(['git', '-C', repo, 'cat-file', '--batch'],
                      input=''.join(f'{s}\n' for _, s in entries).encode(), capture_output=True)
if proc.returncode != 0:
    fail('git cat-file failed')
buf, pos = proc.stdout, 0
for path, sha in entries:
    nl = buf.index(b'\n', pos)
    hdr = buf[pos:nl].split()
    if len(hdr) != 3 or hdr[0].decode() != sha or hdr[1] != b'blob':
        fail('unreadable blob')
    size = int(hdr[2])
    blobs[path] = buf[nl + 1:nl + 1 + size].decode('utf-8', errors='replace')
    pos = nl + 1 + size + 1

allow = []
if '.public-hygiene-allow' in blobs:
    for n, line in enumerate(blobs['.public-hygiene-allow'].splitlines(), 1):
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        entry, sep, reason = line.partition(' -- ')
        f = entry.split()
        if not sep or not reason.strip() or len(f) != 2 or f[0] not in rule_ids:
            fail(f'.public-hygiene-allow line {n}: want `rule-id path-glob -- reason` with a loaded rule id')
        allow.append((f[0], f[1]))


def allowed(rid, path):
    return any(r == rid and fnmatch.fnmatch(path, g) for r, g in allow)


def inline_allowed(rid, line):
    return any(rid in (x.strip() for x in m.split(',')) for m in INLINE.findall(line))


hits, allowed_hits, per_file = Counter(), Counter(), defaultdict(Counter)
deferred, deferred_files = Counter(), set()
for path in [p for p, _ in entries] + [p for p, _ in gitlinks]:
    is_deferred = any(path.startswith(d) for d in defer)

    def record(rid, n):
        if is_deferred:
            deferred[rid] += n; deferred_files.add(path)
        else:
            hits[rid] += n; per_file[path][rid] += n

    for rid, kind, rx in rules:
        if kind == 'path' and rx.search(path):
            if allowed(rid, path):
                allowed_hits[rid] += 1
            else:
                record(rid, 1)
    for lineno, line in enumerate(blobs.get(path, '').splitlines(), 1):
        for rid, kind, rx in rules:
            if kind != 'text':
                continue
            n = len(rx.findall(line))
            if not n:
                continue
            if inline_allowed(rid, line) or allowed(rid, path):
                allowed_hits[rid] += n
            else:
                record(rid, n)

over = {}
if ceiling is not None:
    caps = ceiling['rules']
    for rid, n in deferred.items():
        if n > caps.get(rid, 0):
            over[rid] = {'deferred': n, 'ceiling': caps.get(rid, 0)}
    if len(deferred_files) > ceiling['files']:
        over['_files'] = {'deferred': len(deferred_files), 'ceiling': ceiling['files']}

report = {'head': head, 'tracked_entries': len(entries), 'gitlinks': len(gitlinks),
          'unallowed': dict(hits), 'allowed': dict(allowed_hits),
          'files_with_unallowed_hits': len(per_file),
          'deferred_prefixes': defer, 'deferred': dict(deferred), 'files_with_deferred_hits': len(deferred_files),
          'ceiling_exceeded': over,
          'per_file': {p: dict(c) for p, c in sorted(per_file.items(), key=lambda x: -sum(x[1].values()))}}
print(json.dumps({k: v for k, v in report.items() if k != 'per_file'}))
if out:
    json.dump(report, open(out, 'w'), indent=1)
sys.exit(1 if hits or over else 0)
