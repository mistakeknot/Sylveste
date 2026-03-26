---
artifact_type: plan
bead: Demarch-og7m
stage: design
requirements:
  - F1: Reservation resource limits (.12)
  - F2: Evidence write durability (.27)
  - F3: CODEOWNERS (.26)
---
# Monorepo Consolidation Batch 3 — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Demarch-og7m
**Goal:** Harden multi-agent coordination for 5+ concurrent agents — reservation limits, evidence write durability, and code ownership governance.

**Architecture:** F1 is Go in L1 intermute, F2 is bash in Interverse interspect, F3 is a GitHub config file. All independent — no cross-task dependencies.

**Tech Stack:** Go 1.24 (intermute), bash 5.x (interspect), GitHub CODEOWNERS syntax

---

## Must-Haves

**Truths** (observable behaviors):
- Agent with 10 active reservations gets rejected on 11th attempt with clear error
- TTL > 24h in reservation request is capped to 24h
- interspect evidence writes retry on SQLITE_BUSY instead of silently failing
- Failed evidence writes after retry are logged to stderr (not swallowed)
- PRs to `core/` require review from @mistakeknot

**Artifacts** (files with specific exports):
- [`core/intermute/internal/storage/sqlite/sqlite.go`] Reserve() has per-agent count check + TTL cap
- [`interverse/interspect/hooks/lib-interspect.sh`] exports `_interspect_sqlite_write()`
- [`.github/CODEOWNERS`] exists with pillar ownership mapping

**Key Links:**
- Reserve() count check runs inside the same transaction as conflict check and insert
- `_interspect_sqlite_write()` replaces all INSERT/UPDATE `|| true` patterns

---

### Task 1: Reservation Resource Limits (F1/.12)

**Files:**
- Modify: `core/intermute/internal/storage/sqlite/sqlite.go:1445-1548`
- Modify: `core/intermute/internal/http/handlers_reservations.go:96-148`

**Step 1: Add constants and per-agent limit check in Reserve()**

In `sqlite.go`, add constants near the top of the file:

```go
const (
	// MaxReservationsPerAgent is the maximum number of active (unreleased, unexpired)
	// reservations a single agent can hold simultaneously.
	MaxReservationsPerAgent = 10

	// MaxReservationTTL is the maximum allowed TTL for a reservation.
	MaxReservationTTL = 24 * time.Hour
)
```

In the `Reserve()` function, after the transaction begins (line 1463) and before the conflict query (line 1471), add:

```go
	// Cap TTL to maximum allowed
	if r.TTL > MaxReservationTTL {
		r.TTL = MaxReservationTTL
		r.ExpiresAt = now.Add(r.TTL)
	}

	// Sweep expired reservations (opportunistic cleanup, same transaction)
	_, _ = tx.Exec(
		`UPDATE file_reservations SET released_at = ? WHERE project = ? AND released_at IS NULL AND expires_at <= ?`,
		now.Format(time.RFC3339Nano), r.Project, now.Format(time.RFC3339Nano),
	)

	// Per-agent limit check
	var activeCount int
	err = tx.QueryRow(
		`SELECT COUNT(*) FROM file_reservations WHERE agent_id = ? AND project = ? AND released_at IS NULL AND expires_at > ?`,
		r.AgentID, r.Project, now.Format(time.RFC3339Nano),
	).Scan(&activeCount)
	if err != nil {
		return nil, fmt.Errorf("count agent reservations: %w", err)
	}
	if activeCount >= MaxReservationsPerAgent {
		return nil, fmt.Errorf("agent %q has %d active reservations (max %d): release existing reservations first",
			r.AgentID, activeCount, MaxReservationsPerAgent)
	}
```

Note: Move `r.ExpiresAt = now.Add(r.TTL)` from line 1446 to after the TTL cap, so the capped value is used.

**Step 2: Add TTL validation in handler**

In `handlers_reservations.go`, after the TTL assignment (line 117-120), add a log for capping:

```go
	ttl := 30 * time.Minute
	if req.TTLMinutes > 0 {
		ttl = time.Duration(req.TTLMinutes) * time.Minute
	}
	// TTL cap is enforced in storage layer, but log if request exceeds it
	if ttl > 24*time.Hour {
		slog.Warn("reservation TTL capped", "requested_minutes", req.TTLMinutes, "max_minutes", 1440)
	}
```

**Step 3: Build and test**

Run: `cd core/intermute && go build ./... && go test ./... -v`
Expected: PASS

**Step 4: Commit**

```bash
cd core/intermute && git add internal/storage/sqlite/sqlite.go internal/http/handlers_reservations.go
git commit -m "fix(reservations): per-agent limit (10) + TTL ceiling (24h) + expired sweep

Reserve() now checks active reservation count per agent before insert,
caps TTL to 24 hours, and opportunistically sweeps expired reservations
in the same transaction.

Fixes Demarch-og7m.12"
```

<verify>
- run: `cd core/intermute && go build ./...`
  expect: exit 0
- run: `cd core/intermute && go test ./... -count=1`
  expect: exit 0
</verify>

---

### Task 2: Evidence Write Durability (F2/.27)

**Files:**
- Modify: `interverse/interspect/hooks/lib-interspect.sh`

**Step 1: Add busy_timeout to schema initialization**

Find the schema initialization section (~line 130-232) where `PRAGMA journal_mode=WAL` is set. Add immediately after:

```bash
PRAGMA busy_timeout=5000;
```

**Step 2: Create _interspect_sqlite_write() helper**

Add after the schema initialization section:

```bash
# _interspect_sqlite_write db sql [args...]
# Wraps sqlite3 with retry on SQLITE_BUSY. 3 attempts with exponential backoff.
# Logs failures to stderr instead of silently swallowing them.
_interspect_sqlite_write() {
    local db="$1"; shift
    local sql="$1"; shift
    local attempt=0
    local max_attempts=3
    local delays=(1 2 4)
    local output=""
    local rc=0

    while [[ $attempt -lt $max_attempts ]]; do
        output=$(sqlite3 "$db" "$sql" "$@" 2>&1)
        rc=$?
        if [[ $rc -eq 0 ]]; then
            [[ -n "$output" ]] && echo "$output"
            return 0
        fi
        if echo "$output" | grep -qi "locked\|busy"; then
            attempt=$((attempt + 1))
            if [[ $attempt -lt $max_attempts ]]; then
                sleep "${delays[$attempt-1]:-4}"
            fi
        else
            # Non-contention error — don't retry
            echo "[interspect] sqlite write failed: $output (sql: ${sql:0:80})" >&2
            return "$rc"
        fi
    done

    echo "[interspect] sqlite write failed after $max_attempts attempts (BUSY): ${sql:0:80}" >&2
    return 5
}
```

**Step 3: Replace critical || true patterns**

Search for evidence insertion patterns like:
```bash
sqlite3 "$_INTERSPECT_DB" "INSERT INTO ..." 2>/dev/null || true
```

Replace with:
```bash
_interspect_sqlite_write "$_INTERSPECT_DB" "INSERT INTO ..."
```

Focus on the evidence insertion paths — do NOT change SELECT queries or schema migrations.

Key insertion sites to convert:
- Evidence row insertions in `_interspect_consume_review_events()`
- Modification tracking in `_interspect_apply_routing_override()`
- Canary sample insertions in `_interspect_canary_record()`
- System breaker log (from Batch 2's F2)

**Step 4: Syntax check**

Run: `bash -n interverse/interspect/hooks/lib-interspect.sh`
Expected: exit 0

**Step 5: Commit**

```bash
cd interverse/interspect && git add hooks/lib-interspect.sh
git commit -m "fix(interspect): evidence write durability — busy_timeout + retry + logging

Sets PRAGMA busy_timeout=5000 and introduces _interspect_sqlite_write()
with 3x retry (1s/2s/4s backoff) for INSERT/UPDATE operations. Failed
writes after retry log to stderr instead of being silently swallowed.

Fixes Demarch-og7m.27"
```

<verify>
- run: `bash -n interverse/interspect/hooks/lib-interspect.sh`
  expect: exit 0
</verify>

---

### Task 3: CODEOWNERS (F3/.26)

**Files:**
- Create: `.github/CODEOWNERS`

**Step 1: Create CODEOWNERS file**

```
# Demarch monorepo — code ownership for review routing
# See: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners

# Default: all paths require owner review
* @mistakeknot

# L1 Kernel — intercore + intermute
/core/intercore/ @mistakeknot
/core/intermute/ @mistakeknot

# L2 OS — Clavain, Skaffen, Zaka, Alwe, Ockham
/os/Clavain/ @mistakeknot
/os/Skaffen/ @mistakeknot
/os/Zaka/ @mistakeknot
/os/Alwe/ @mistakeknot
/os/Ockham/ @mistakeknot

# L1 SDK
/sdk/interbase/ @mistakeknot

# Key Interverse plugins
/interverse/interspect/ @mistakeknot
/interverse/interflux/ @mistakeknot
/interverse/interlock/ @mistakeknot

# L3 Apps
/apps/Autarch/ @mistakeknot
/apps/Intercom/ @mistakeknot

# CI/CD and GitHub config
/.github/ @mistakeknot

# Root config
/CLAUDE.md @mistakeknot
/AGENTS.md @mistakeknot
/PHILOSOPHY.md @mistakeknot
```

**Step 2: Commit**

```bash
git add .github/CODEOWNERS
git commit -m "chore: add CODEOWNERS for review routing at 3+ contributors

Maps all pillars and key Interverse plugins to @mistakeknot.
Wildcard fallback ensures no path is unowned.

Fixes Demarch-og7m.26"
```

<verify>
- run: `test -f .github/CODEOWNERS && echo "exists"`
  expect: contains "exists"
</verify>
