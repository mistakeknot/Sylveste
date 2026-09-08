# Beads Two-Machine Sync — Verified State

> How bead state moves between Clavain (MacBook) and zklw (dedi), what differs
> between them, and which differences are deliberate. Companion to
> `publish-machine-roles.md`, which covers the *publish* role rather than beads.
>
> Verified end to end 2026-07-31 by observing hooks fire and beads arrive, not
> by confirming files were present. That distinction matters: this protocol had
> already failed once because a hook was installed at a path git ignores, which
> every file-presence check would have called healthy.
>
> Re-verified 2026-08-01 after the dependency-actor repair and the untracking of
> `.beads/metadata.json`: a cross-machine export now moves **7 rows for one
> changed bead**, down from 3,313, measured in both directions on the live pair.

## The protocol

`.beads/issues.jsonl` is the git-tracked transport. Each machine keeps its own
Dolt database; the JSONL is how they reach each other.

| Direction | Mechanism | Trigger |
|---|---|---|
| Dolt → JSONL | guarded merge (`scripts/beads-auto-export.sh`), then a dedicated commit | `post-commit` |
| JSONL → Dolt | classify, `bd import` the unambiguous rows, verify (`scripts/beads-import-merged.sh`) | `post-merge` |
| deletions | `scripts/beads_apply_deletions.py`, after a *verified* import only | `post-merge` |

## Repaired 2026-09-07: record-level, preserve-and-flag, durable evidence

Topology is unchanged — Clavain and zklw, one Dolt each, git in between — but
the transport now reasons per record, remembers what it verified, and never
resolves ambiguity by picking a host or a timestamp.

**Provenance is a persisted per-record baseline**, `.beads/transport/baseline.json`
(per machine, gitignored, mode 0700): for every record, the semantic hash of
the last content on which the transport and the database were seen to agree.
Not HEAD. After a preserve-and-flag export HEAD holds the transport's side of a
conflict, and a pass that took HEAD as provenance would read the database's side
as a fresh one-sided change and publish it. The baseline moves only on
agreement (equal on both sides, a verified export, a verified import); conflicts
leave their entry alone, which is what keeps a conflict a conflict on the next
pass. With no entry for a record, a difference is a conflict until the sides
agree — or the integrator seeds the baseline from a reviewed reconciliation
(`check_beads_jsonl_dolt_sync.py --state-dir .beads/transport --seed-baseline <jsonl>`).

**Semantic comparison** ignores derived counts (`comment_count`,
`dependency_count`, `dependent_count`, `_type`), normalises timestamps and
list order, and drops empty fields. The two hosts' snapshots differ on derived
counts for shared rows; treating those as edits would manufacture conflicts.

**Export** (`post-commit`, or `scripts/beads-auto-export.sh --manual`): a
private `bd export` to a temp file, every record classified against the
transport and the baseline, then a merged transport written and atomically
replaced only if its bytes have not moved since the snapshot. Database-side
changes and new records apply. Rows only the transport holds (pulled but not
imported, or absent here) are preserved — absence is not deletion. Conflicted
IDs keep their current transport version; every version is kept under
`.beads/transport/evidence/<stamp>/` (private) and the IDs and hashes go to
stderr and `.beads/transport/status.json`. Safe records never wait on
conflicted ones. The pre-commit drift guard runs the same record-level check
on any hand-staged JSONL and blocks only a snapshot that omits database-side
work.

**Import** (`post-merge`, `--retry`, `--full`): the added lines of the range's
diff are validated as records, then classified *before* bd sees any of them.
A row the database lacks, or already holds with equal content, is always safe.
For an existing row with different content two things are required. First,
git provenance: **every two-parent merge in the admitted range is inspected**,
and a record that differs from that merge's base on both of its sides changed
on both hosts since they last agreed — a `both_changed_since_merge_base`
conflict whichever side the merge took and whatever the timestamps say. This
is what protects an edit that was already exported (every commit exports):
locally that row equals the pre-merge transport and the baseline, so baseline
equality alone would hand it to bd and the newer incoming row would win. Only
then, second, the local-state rule: the local row must be unchanged since the
last verified state (persisted baseline, or the pre-merge transport);
otherwise it is an independent local modification. `--full` has no git
provenance, so it imports absent rows, confirms equal ones, and holds every
differing existing record as `no_git_provenance`. A range git cannot explain
(the before-commit is not an ancestor of HEAD, an octopus merge, no common
ancestor) is an explicit `ancestry_unknown` incomplete result — never an
invented baseline. Every held-back record goes to evidence with every version
(incoming, database, before, base, ours, theirs). bd's strictly-newer guard
stays as the second line of defence for what is handed over (it cannot protect
a modified local row from a *newer* incoming one; the classifier can). Success
is `bd import` exiting 0 with a parseable reply **and** a native verification:
a private export shows every importable row present with the same content or
legitimately kept back by bd. Until then the batch is pending:
`.beads/transport/pending-import.json` holds the exact before/after commits,
the reason, and the merge ancestry used, `pending-import.jsonl` the rows. A
pending batch is picked up by the next merge that runs the hook (the range
starts at the pending before-commit and classifies with the ancestry it
recorded) and by `--retry`. **Git runs no hook for a pull that is "Already up
to date"**, so such a pull retries nothing; the
batch is instead announced by every later commit (post-commit) and push
(pre-push) and by `beads-transport-setup.sh check` until it is loaded. An
unresolvable before-commit is an explicit incomplete result with `--full` as the
deliberate, still bounded and verified, whole-file import — never an unbounded
one. The deletion ledger runs only after a verified import.

**Native `bd hooks run post-merge` imports the JSONL by itself.** Measured on
bd 1.1.2 (`20e493e56`): it applies every strictly-newer row. bd maps the
dotted config key `import.auto` to the environment as `BD_IMPORT_AUTO` and
returns from its auto-import when that is false — verified against the
installed binary with a positive control. The tracked `post-merge` therefore
puts bd's block *after* Sylveste's and sets `BD_IMPORT_AUTO=false` for the
remainder of that hook process only: bd's chained hooks still run, its
unclassified import does not, and nothing is written to any config or shell
profile. No file at `transport-disabled.jsonl` (the retired mechanism) has
any effect. `tests/test_bd_import_guard.py` holds bd to the native behaviour
and runs the actual tracked hook against a real bd; the hook suite proves the
override reaches bd's process through a real pull and leaks nowhere.

**Foreign hooks are never retired silently.** `install` inspects the directory
that is effective *before* it writes anything: a hook there is acceptable only
if every non-comment line outside the four transport sections is retained by
the tracked hook (an older copy of these hooks, a bare bd shim). A custom hook,
or a hook name Sylveste does not ship, refuses the install by name with
`core.hooksPath` untouched. Nothing is chained or wrapped: re-running an old
transport hook would reintroduce the unguarded native import or export twice.

**The database is verified before every export and import.** `bd -C <linked
worktree>` resolves the `.beads/` *above* the worktree (on Clavain, the
`~/projects` workspace database, 767 issues), while a cwd run follows the
worktree's `.git` file to the main checkout's `Sylveste` database — verified
with both `bd context --json` and `bd info` on 2026-09-07. Every helper runs
bd from the checkout, never with `-C`, and refuses when the reported
`beads_dir` is not the main checkout's `.beads/` (`BEADS_TRANSPORT_EXPECT_PROJECT`
adds a project-id check). That is the sylveste-vqlu shape, closed at runtime.

**Serialization**: one kernel `flock` per database, held by a child process for
as long as the caller lives, at
`$HOME/.cache/sylveste-beads-transport/<hash>.flock` — the same path whatever
`TMPDIR` or `XDG_RUNTIME_DIR` a login shell, launchd job or IDE hook has; with
no `HOME` there is no lock and the operation refuses. The hash is of the
physical `.beads` directory, normalised from either `bd context --json`
(`beads_dir`) or legacy `bd info` (the data directory beneath it), so two
processes that asked bd differently contend for one lock; a lookup that is
not a `.beads` directory is no identity and refuses. No stale-lock takeover
exists to race; a SIGKILLed hook releases the lock with its holder. An import
that cannot take the lock, or cannot verify its database, leaves the
holder's pending state untouched and records the deferral in the log and
under its own status key. Bounded subprocesses kill the whole process group,
not only the leader.

### Setup and check

```bash
scripts/beads-transport-setup.sh            # check: exit 1 on any problem
scripts/beads-transport-setup.sh install    # make the tracked hooks effective HERE
scripts/beads-transport-setup.sh check --json --expect-project 07e89680-8485-4489-a63a-9105595860b2
```

The hooks are tracked files in `.beads/hooks/`; what a clone lacks is git's
decision to run them (`core.hooksPath`). The isolated roadmap clone had every
hook file and ran none. `check` reports the *effective* hook path, the
transport blocks in each hook (foreign sections counted, never rewritten), the
database bd resolves from this checkout, pending/conflict state, and every
other worktree's effective path. `install` in a linked worktree enables
`extensions.worktreeConfig` (one-time, shared) and writes `core.hooksPath` into
that worktree's own `config.worktree`, then proves every other worktree's
effective path is unchanged; it refuses when the database binding is not
verified and never initialises a database. `bd hooks install` is composed, not
replaced — it does not install Sylveste's transport blocks.

### Recovering a pending import

```bash
scripts/beads-import-merged.sh --status     # what is pending, since which commit, why
scripts/beads-import-merged.sh --retry      # idempotent; rows classified again first
scripts/beads-import-merged.sh --full       # only when the before-commit is unknown
```

### Conflicts

`.beads/transport/conflicts.json` carries every open conflict with its reason
(`both_changed_since_baseline`, `equal_updated_at_different_content`,
`no_baseline`, `local_changed_since_verified`, `native_guard_kept_local`,
`removed_from_transport_but_changed_in_database`), hashes, first/last seen and
the evidence directory holding each version. Resolve by editing the bead
natively on the host whose version should win and letting the next export or
import carry it; once both sides agree the entry clears itself. Never resolve by
copying a version into the JSONL by hand. Autonomous reprioritization stays
disabled while conflicts are open.

### Canary

1. Mac: `bd create "canary <date>"`, then an ordinary commit — the post-commit
   export commit appears; `git push`.
2. zklw: `git pull` — `bd show <id>` answers; `.beads/transport/status.json`
   says `import: verified`.
3. zklw: `bd update <id> --status closed`, ordinary commit, push.
4. Mac: `git pull` — `bd show <id>` is closed; status verified; no pending, no
   conflicts.

No manual export/import may substitute for any step.

`beads-import-merged.sh` hands bd only the rows the merge changed, after
classifying them. A full `bd import` of the file measures ~49s on Clavain, and
on zklw it does not finish at all — see below. It would run on every pull; the
retired importer had been avoiding that incidentally, by filtering before
importing. git already knows which lines changed and every issue is one line,
so the filter costs nothing and bd still applies its guard per row. When the
diff cannot be determined (the before-commit does not resolve, or git cannot
explain the range) the helper does **not** fall back to importing the whole
file unbounded: it records an explicit incomplete result with pending state and
exits 1, and the deliberate recovery is `scripts/beads-import-merged.sh --full`
— still classified, bounded and verified. `--full` has no git provenance, so it
imports rows the database lacks and confirms rows already equal, and it **holds
every existing record whose content differs** as a `no_git_provenance` conflict
with both versions in evidence; whole-file scope is not permission to choose an
exported concurrent edit by timestamp. An import that silently skips another
machine's work and one that silently overwrites this machine's are both
failures; neither is traded for the other.

**It helps a lot.** Measured 3 rows on a same-machine merge (49s → 1s). It used
to degrade to **3,313 rows** on a cross-machine one — exactly the case it was
written for — until the dependency-actor divergence below was repaired. A
cross-machine merge now hands over **7 rows for one changed bead**, and the pull
completes in about 1.5s.

**The import is bounded at 120s** (`BEADS_IMPORT_TIMEOUT`) and says so on
timeout. Unbounded, `git pull` never returns: observed twice on zklw, with
`bd import` blocked in `futex_wait` against its own Dolt server — 5 seconds of
CPU in 5 minutes, not growing, socket open, other bd processes live. The pull
had to be killed by hand, and the deletion pass that runs after the import never
ran until it was. A timeout is not a silent skip: the rows are still in the
file, and the message names the command that loads them.

### The dependency actor the two machines could never agree on (resolved)

`bd export` is deterministic — two consecutive exports on one machine are
byte-identical. The two machines nevertheless disagreed about
`dependencies[].created_by` on **3,589 of 3,657** shared dependency rows:
`"Claude Code"` on zklw, `"mistakeknot"` on Clavain, everything else about the
row identical. Roughly 3,308 beads carry dependencies, so every export that
alternated machines rewrote all of them. That is the source of the recurring
`-3805/+3804` commits in this file's history.

**It was not bd stamping the importing actor**, which is what this document said
for a while and what the bead was written around. bd 1.1.2 preserves the file's
dependency `created_by` in every path constructible against a real database:
creating the issue and its dependency together, adding a dependency to an issue
the database already holds, and re-importing a genuinely-newer row. What bd has
no operation for is *updating* the actor on a dependency that already exists
locally.

Preserve-on-create plus ignore-on-update is what made it permanent. Each
database stamped its own git identity once, long ago, under an older bd, and no
import since could reconcile it — so the field was a fixed point per machine and
the file oscillated between them forever. A shared `BEADS_ACTOR` would not have
fixed it; it would only have stopped new rows from joining the set.

**Repaired directly, in both databases** (`scripts/beads_normalize_dep_actors.py`).
The field was resolved rather than collapsed, because the originator is
recoverable: issue-level `created_by` agrees across the machines on 3,807 of
3,811 issues, and for 3,551 divergent dependencies exactly one machine's value
equals the dependent issue's own creator — a dependency is created in the same
breath as the issue that carries it. 14 more resolve because one side is a
session id and the other is a machine's git identity, which is bd's fallback in
the hook context that did the historical importing.

| resolution | rows |
|---|---:|
| dependent issue's creator (agreed on both machines) | 3,551 |
| exactly one side is a session id | 14 |
| neither — lexicographic minimum, listed by id | 24 |

The 24 are the only attribution actually lost. The tiebreak is arbitrary on
purpose but not machine-dependent: "whichever side loses" would resolve one way
on each machine and the row would resume oscillating.

Measured by exporting from each machine and comparing:

| | before | after |
|---|---:|---:|
| issues differing between the machines | 3,314 | 12 |
| dependency rows disagreeing on actor | 3,589 | 0 |
| cross-machine export, no work in it | 3,313 rows | **6 rows** |
| cross-machine export, one bead changed | 3,314 rows | **7 rows** |

Symmetric in both directions, measured on the live pair.

The **6-row floor** is not churn from this design — four beads were created
independently on both machines and differ in `created_at`, which no import can
reconcile; one carries a dependency on a bead ID that does not exist; one has a
one-sided `started_at`. Tracked as `Sylveste-keb3`.

**If it ever recurs**, both machines export to temp paths and run the script with
`--local`/`--peer` swapped; it is idempotent and reports 0 rows to change when
there is nothing to do. Run it on both, or the machine you skipped will simply
write its values back.

Both machines set `core.hooksPath = <repo>/.beads/hooks`, so `.git/hooks/` is
**never executed**. Anything installed there is inert. Confirmed on both.
`core.hooksPath` is set by `bd hooks install`, not by us.

Both machines run **bd 1.1.2** against **schema v53**.

## One export mechanism, chosen

There are two things that could export the JSONL, and exactly one is enabled.

**`scripts/beads-auto-export.sh` (post-commit) is the live one.** It probes,
exports, and commits the result as its own commit.

**bd's built-in auto-export is off**, explicitly, in the tracked
`.beads/config.yaml`:

```yaml
export.auto: false
export.git-add: false
```

Why off, on the evidence rather than on preference:

- `export.auto` only *writes* the file. It never commits it, and only the
  committed copy is pushed — so on its own it strands a dirty `issues.jsonl` in
  the working tree indefinitely. Our post-commit path exports *and* commits,
  which is what a git-carried transport actually needs.
- `export.git-add` stages the export into whatever commit is forming, which
  widens `git commit -- <paths>` past the paths named. Observed on zklw: a
  one-path commit produced a two-file commit.

Verified after the change, on both machines: a pathspec commit contains exactly
the paths named, and the export arrives as a separate
`beads: sync export (automated)` commit.

### Why this was ever in doubt

Neither key had ever been *set*. Each machine inherited its bd version's
default, and the defaults disagree:

| bd version | `export.auto` | `export.git-add` |
|---|---|---|
| 1.0.0 | false | false |
| 1.0.2 | **true** | **true** |
| 1.1.x | false | false |

So zklw (1.0.2) exported on every write and Clavain (1.0.0) exported never, and
nobody had chosen either behaviour. That is the entire reason
`.beads/issues.jsonl` sat two days and 63 issues stale on one machine while the
other stayed perfectly current — the defect the previous three goals were
circling.

Setting both explicitly is the durable fix: the file is tracked, so both
machines read the same values whatever bd they run, and a future upstream
default flip cannot silently reintroduce either behaviour. It also fixed the
widening at bd 1.0.2, before either machine was upgraded.

## Upgrading bd

`bd` is one binary per machine serving **every** beads database on it (43 on
Clavain, 59 on zklw). bd 1.1.2 does **not** migrate an old database lazily — it
fails to open it (`column "started_at" could not be found`). So upgrading the
binary means migrating every database on that machine, not just this one.

The procedure that worked, per database:

```bash
# Pre-count must come from the OLD binary. The new one cannot open an
# unmigrated database at all, so "the new binary exported N" says nothing
# about what was there before.
( cd "$repo" && old-bd export --all -o pre.jsonl )
( cd "$repo" && BD_ALLOW_REMOTE_MIGRATE=1 bd migrate --yes )
( cd "$repo" && bd export --all -o post.jsonl )
# verify by comparing issue counts, not by the migrate exit code
```

`BD_ALLOW_REMOTE_MIGRATE=1` is required because bd refuses to migrate a
remote-backed database unattended: independent migration on two clones of a
*shared* remote forks the schema silently. That hazard does not apply between
Clavain and zklw — they do not share a Dolt remote and never `dolt pull` from
each other (see below) — so each migrates its own copy.

Result 2026-07-31: Sylveste went v23→v53 on Clavain and v32→v53 on zklw, with
3,804 issues + 1 memory preserved on each, ID sets identical.

### If a migration refuses with "dirty tables"

```
pending schema migrations alter pre-existing dirty tables: config
```

Upstream [#4566](https://github.com/gastownhall/beads/issues/4566) (closed):
"dirty working set deadlocks schema migration — `bd dolt commit` can't clear it
because it also triggers init schema". The remedy bd prints is therefore the one
thing that cannot work: the command told to clean the working set re-dirties it
on startup. Commit the working set with the `dolt` CLI instead, bypassing bd
entirely:

```bash
cd <dolt data dir>          # .beads/dolt, or ~/.beads/shared-server/dolt
dolt sql -q "use <db>; call dolt_add('.'); call dolt_commit('-m', 'commit working set before schema migration');"
```

Then re-run the migration. This cleared all 8 affected databases on Clavain.

### Databases that need `bd bootstrap`, not migration

16 databases (3 on Clavain, 13 on zklw) have a `.beads/` directory but no local
database — they report `bd where` / `bd bootstrap` hints rather than a schema
error. **These were already broken before the upgrade**, verified by running the
old binary against them. They are not migration casualties. Recovering one means
`bd bootstrap` to re-clone from its remote, which *replaces* local data, so it is
a per-project decision rather than a batch operation. Tracked as `sylveste-esjb`.

```
Clavain (3): jawncloud  phosphene  underground-beets
zklw   (13): agents  FLUXrig  garden-salon  intervox  intrdrm  oodacademy
             prodspecs  productrecs  shadow-work  spellswords  tropescraper
             wi2c  zahro
```

Note `shadow-work` appears here for zklw but migrated cleanly on Clavain — the
two machines do not have the same set of working databases, so this list is
per-machine rather than a property of the repo.

## The trap that cost the most

`.beads/metadata.json` carries a `dolt_server_port` field that bd 1.1.2 warns
is deprecated "(can cause cross-project data leakage)". It is a real hazard, not
a style note.

Copying a `.beads/` directory elsewhere to experiment on it does **not** isolate
it. Deleting `.beads/dolt-server.port` is not enough: bd falls back to
`dolt_server_port` in `metadata.json` and connects to the *original* machine's
live server. A "sandbox" migration run this way applied 30 schema migrations to
the production database instead of the copy.

To actually isolate a copy, remove the port from `metadata.json` too — or copy
neither file and let bd start its own server.

### The same file was also a cross-machine channel (closed)

`.beads/metadata.json` names machine-local resources — `dolt_database`,
`dolt_mode`, and that deprecated `dolt_server_port` — and it was **git-tracked**,
so the port that caused the trap above was not merely present on this machine, it
was committed. zklw carried Clavain's `57745` while actually serving on `42527`
from its own untracked `.beads/dolt-server.port`: a wrong value sitting in a
shared file, inert only because no bd version happened to honour it.

`bd init` makes its **own git commit**. Building the two-machine sandbox for the
deletion work, a second `bd init` committed its freshly-written `metadata.json`,
the other repo pulled it, and that machine silently repointed at the *other
machine's database*. Both then read and wrote one database while every check
that asked "are these isolated?" answered yes, because each was still reading
its own `.beads/` path. Deletions appeared to propagate before any mechanism
existed to propagate them. `git update-index --skip-worktree` did not survive it.

**Untracked as of `Sylveste-sb6z`.** Each machine keeps its own copy on disk;
`.beads/.gitignore` now carries `metadata.json` and git no longer tracks it.
Verified: a cross-machine pull leaves the local pointer byte-identical, and each
machine still answers from its own database.

Two things to know:

- **The pull that lands the untracking deletes the file**, because git removes a
  path it has stopped tracking. Back the file up on each machine first and
  restore it after. Both machines needed this; it is a one-time cost that is easy
  to discover the hard way.
- **A fresh clone no longer carries a pointer.** It needs `bd bootstrap` (or
  `bd init`) before `bd import .beads/issues.jsonl`. Covered by
  `tests/test_beads_metadata_isolation.sh` scenario 4.

The test asserts on the **connected database**, never on a path — it probes with
a bead that exists in exactly one of two repositories, which is the question a
path cannot answer and the reason the original sandbox failure went unnoticed.
Scenario 0 asserts that *this* repository does not track its own pointer: the
first attempt shipped the ignore rule while leaving the file tracked, where it
does nothing, and both the commit and CI were satisfied. `git rm --cached` staged
the removal and `git commit -F msg -- <paths>` naming that file undid it, because
the pathspec form commits the working tree and ignores the index.

## Drift register

### Resolved

**bd version.** Was 1.0.0 (Clavain) vs 1.0.2 (zklw); both now 1.1.2. This was
the root of the hook-shim churn — each bd rewrites its managed blocks to its own
version string, so the two machines flipped
`# --- BEGIN BEADS INTEGRATION v1.0.x ---` back and forth. Verified fixed by
observation: after pulling the other machine's hooks, `bd hooks install --force`
on zklw produced an empty diff. Both machines now generate byte-identical hook
content. `bd hooks install` only rewrites between its own markers — the SYLVESTE
blocks in those files survive it, checked against a backup.

**Dolt schema.** Was v23 (Clavain) vs v32 (zklw); both now v53. Worth noting
that a 9-version schema divergence went unnoticed for months without breaking
anything, which is a genuine point in favour of a schema-tolerant JSONL
transport over Dolt-level replication.

**`setsid` is Linux-only.** The post-commit Dolt auto-push block used it
unconditionally, so on macOS the subshell failed, `|| true` swallowed it, and
`.beads/push-hook.log` was never created — no output, no error, no trace. It now
falls back to a plain background job and always writes the log.

**Push privileges.** Previously Clavain pushed `main` directly (the remote
reported `Bypassed rule violations`) while zklw was rejected. `enforce_admins`
is now **true** on `main`, so both machines take the same route: push to
`autosync/<machine>`, wait for `Generator and parity checkers`, then
fast-forward `main`. The asymmetry recorded here previously no longer exists.

### Accepted, with reasons

**Issue-ID prefix casing differs.** zklw creates `sylveste-vftd`; Clavain
creates `Sylveste-v4ub`. Both resolve, and the drift checker compares whole IDs,
so mixed casing is cosmetic — a tell of which machine filed a bead.

**Dolt remotes differ, and are not shared.** zklw's is
`file:///home/mk/projects/Sylveste/.beads/remote/Sylveste` (a directory on zklw);
Clavain's is `git+https://github.com/mistakeknot/Sylveste.git`. Neither is a
cross-machine channel. This is why the two machines can migrate schema
independently without the fork hazard bd warns about — and why the git-tracked
JSONL is the only thing actually carrying beads between them.

**Dolt mode differs per project, not per machine.** Sylveste runs a managed
per-project sql-server; other projects (cujgel, and most of the smaller ones)
run embedded, which is also what a fresh `bd init` now produces. `bd sql` is
*not supported in embedded mode*, so `check_beads_jsonl_dolt_sync.py` only works
in server mode — a trap if it is ever reused elsewhere. This is why
`beads_apply_deletions.py` reads local state with `bd show --json` instead: the
same dependency is what made the retired importer inert on fresh clones.

**`.beads/embeddeddolt` on Clavain is dead.** 42M, last written 2026-04-07, zero
files touched since. The live server's cwd is `.beads/dolt`. Left in place
rather than deleted, but it is not the database and should not be mistaken for
one.

## The signer asymmetry is handled, not assumed

zklw is `role: signer`; Clavain is `role: verifier` with only
`.clavain/keys/authz-project.pub`. Same key fingerprint (`3d1c3001d533c5a9`).
So `.beads/push.sh` genuinely cannot work on Clavain, and the git-tracked JSONL
is the **only** egress for bead state there.

Checked whether anything quietly depends on that push succeeding:

- `.beads/push.sh` exits **1** when it refuses, with a message naming the
  reason. It does not fail open.
- `.beads/close-and-sync.sh` runs under `set -euo pipefail`, so it aborts on
  that exit rather than reporting a close as synced.

Both correct. The asymmetry is visible at every call site that could be misled
by it.

## Limitations

**A failing probe is loud, not silent.** `beads-auto-export.sh` decides whether
to export by running the same checker that guards commits. If that checker
cannot run, the script now says so on stderr and names the fix, instead of
skipping quietly. It previously conflated "bd absent (cloud session)" with "the
probe ran and failed" — and the second went silent for a while today when a
schema mismatch broke `bd sql`, which is the exact failure shape this whole
mechanism was built to replace.

Note the branch keys on *"did it produce a verdict"*, not on the exit code: the
checker is also the pre-commit guard, so it exits non-zero precisely when it
finds drift, which is when an export is wanted.

**Deleting a bead takes one extra command, and only one.**

```bash
bd delete <id> --force                          # or skip this and pass --delete-local
scripts/beads-confirm-deletion.sh <id>          # records intent, exports, commits
git push
```

`bd import` is upsert-only: it creates and updates, never deletes. Absence
cannot be the signal either — an export missing a bead means "deleted there" or
"not created there yet" or "filtered out" (`bd export` omits infra beads by
default), and acting on absence would delete live work.

So intent is recorded explicitly in `.beads/deletions.jsonl` — append-only,
git-tracked, committed in the *same commit* as the export that acts on it. Split
across two commits, the other machine can pull the export without the ledger and
resurrect the bead in the window between. `beads_apply_deletions.py` runs after
the import on `post-merge` and deletes exactly the ids named, refusing any whose
local row is newer than the deletion record (someone worked it after the other
machine dropped it) and saying so on stderr.

`beads-confirm-deletion.sh` refuses if this database is missing beads the shared
file has. It exports, and an export writes the local database over the file, so
anything the file holds and Dolt lacks is destroyed by it — the same reason
`beads-auto-export.sh` refuses in that state. The first version called
`bd export` directly and skipped the check. A probe caught it: zklw's import had
been killed mid-flight, its database was five beads behind, and confirming one
deletion produced an export with **six** beads missing — including the bead
tracking this work. It was on an unmerged branch, so nothing was lost, but that
was luck. Covered by scenario 8 of `tests/test_beads_deletion_propagation.sh`,
which fails when the guard is removed.

Measured before and after, on two real Dolt databases with a bare remote between
them, in both directions:

| | A deletes → B | B deletes → A |
|---|---|---|
| before | survived on B, resurrected on A | survived on A, resurrected on B |
| after | gone on B, stays gone | gone on A, stays gone |

**bd does not support tombstones.** This document previously said bd 1.1.2
"understands `tombstone` rows on import, so this is now *fixable*". That was
wrong, and it was wrong in the direction that matters: v1.1.0 **removed**
tombstones (release note: *"removed SQLite backend, JSONL sync, 3-way merge,
tombstones, storage factory, daemon stubs (8-phase refactor)"*). The only
surviving mention is `bd import` skipping rows whose status is `tombstone` —
backward compatibility for old exports, not a deletion channel. The claim came
from reading a removal as a feature; the ledger above exists because there was
nothing to switch on.

**Expect merge conflicts on `.beads/issues.jsonl` when both machines export.**

It is a ~3,900-line generated file and both ends rewrite it, so git conflicts on
it are routine rather than exceptional. Do not hand-resolve the hunks. Take the
incoming side, then let the guarded helpers do the rest:

```bash
git show MERGE_HEAD:.beads/issues.jsonl > .beads/issues.jsonl   # take incoming
git add .beads/issues.jsonl && git commit --no-edit             # finish merge
scripts/beads-import-merged.sh ORIG_HEAD                        # classify, import, verify
python3 scripts/beads_apply_deletions.py                        # their deletions, if the import verified
scripts/beads-auto-export.sh --manual                           # guarded merge back out
```

Note that finishing a conflicted merge with `git commit --no-edit` runs the
commit hooks (pre-commit, post-commit) but **not** `post-merge`, so the import
and the deletion pass have to be run by hand here. That is the one path where
the automation does not cover for you.

Taking the incoming side first is deliberate: the helper classifies with git's
own provenance — every two-parent merge in the range `ORIG_HEAD..HEAD`,
including the one just made, with the merge base of its two parents — so a
record edited on both hosts since they last agreed is a conflict
(`both_changed_since_merge_base`) whichever side the merge took and whatever
the timestamps say; every version goes to evidence and neither host's is
chosen. Rows only the transport holds are preserved, unrelated one-sided rows
apply, and the guarded export re-adds local database-side work without touching
the conflicted ones. Because `git commit --no-edit` does not run `post-merge`,
the explicit `scripts/beads-import-merged.sh ORIG_HEAD` call is required on
this path — the merge commit's parents are what the helper reads, so it must
run after that commit. Every two-parent merge in the admitted range is
inspected, whether it diverged from `ORIG_HEAD` or happened entirely upstream;
a dependency-PR merge is harmless because its records did not diverge, not
because of where its parents sit, and a fast-forward across such merges is
ordinary. A range git cannot explain (a rebase, any octopus merge in the
range, no common ancestor) is an explicit incomplete result; `--full` is the
deliberate way past it, and it still holds differing existing records rather
than choosing by timestamp. Never a bare `bd export` over the transport, and `bd backup
sync` is a Dolt backup, not cross-host replication.

## Retired: `scripts/beads_safe_import.py`

Deleted, not left dormant. bd 1.1.2's own `bd import` enforces the rule the
script was written for — "updated_at is strictly newer; older rows are skipped;
rows with the same updated_at keep every local column" — *inside the
transaction* rather than as a pre-filter, with `--allow-stale` as the deliberate
override.

Equivalence was measured, not inferred, on a real bd database:

| case | `beads_safe_import.py` | `bd import` |
|---|---|---|
| stale row vs locally closed bead | held closed | held closed (`stale_skipped_ids`) |
| equal timestamps, differing status | held closed | held closed |
| genuinely newer row | applied | applied, with a field-level diff |
| bead absent locally | created | created |

The last two rows are not decoration. A mechanism that imports *nothing* passes
the first two, and a green result from a check that inspects nothing is the
failure mode this document keeps running into.

bd is better on three counts beyond the transaction boundary:

- **It works in embedded mode.** Our script read local state via `bd sql`,
  which does not exist in embedded mode — and embedded is what a fresh
  `bd init` produces in 1.1.2. The script was inert on any new clone, and went
  inert *here* on 2026-08-01 when a schema mismatch broke `bd sql`; that is the
  window the three `REFUSED` entries in `.beads/auto-export.log` sit in.
- **It reports what it changed** (`updated_issues` with a field-level summary),
  so an import that alters local state is visible rather than inferred.
- **On a tie it still merges labels, comments and dependencies.** Ours dropped
  them, discarding the other machine's comments on any same-second write.

What replaced its test is `tests/test_bd_import_guard.py`, which asserts the
same properties against real bd. Those tests can now fail on a bd upgrade with
nothing in this repo having changed — which is the honest consequence of
depending on someone else's guarantee, and better than a copy that silently
drifts from it.
