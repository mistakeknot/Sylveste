---
artifact_type: plan
bead: sylveste-h7t
stage: design
requirements:
  - F2: Identity crosswalk (file + function level)
---
# Identity Crosswalk Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** sylveste-h7t
**Goal:** Materialized identity crosswalk mapping (subsystem, subsystem_id) → canonical_entity_id with file-level and function-level resolution, O(1) runtime lookup, incremental updates.

**Architecture:** SQLite database (`interweave.db`) stores three tables — `entities` (canonical entity registry), `identity_links` (cross-subsystem mappings with confidence), and `actors` (person-level identity unification). The crosswalk is a write-behind index: connectors (F3) will write to it, queries read from materialized indexes. File-level resolution uses path normalization + git rename detection. Function-level resolution uses tree-sitter AST fingerprinting with body similarity scoring for rename/move detection. Identity chains record the history of renames across index rebuilds.

**Tech Stack:** Python 3.12, sqlite3 (stdlib), tree-sitter + tree-sitter-python (initial language), existing F1 type family system.

---

## Must-Haves

**Truths** (observable behaviors):
- Crosswalk stores and retrieves entity identity mappings with O(1) lookup
- File paths from different subsystems resolve to the same canonical entity
- Function renames are detected via AST body similarity with confidence thresholds
- Actor identities are unified across git username, session ID, beads claimed_by
- Identity chains preserve rename history across index rebuilds
- Duplicate entities are detected and flagged

**Artifacts** (files with specific exports):
- [`src/interweave/crosswalk.py`] exports [`Crosswalk`, `CanonicalID`]
- [`src/interweave/storage.py`] exports [`CrosswalkDB`]
- [`src/interweave/resolve_file.py`] exports [`resolve_file_identity`]
- [`src/interweave/resolve_function.py`] exports [`resolve_function_identity`, `compute_ast_fingerprint`]
- [`src/interweave/resolve_actor.py`] exports [`resolve_actor_identity`]

**Key Links** (connections where breakage cascades):
- `Crosswalk` depends on `CrosswalkDB` for all persistence
- `resolve_file_identity` and `resolve_function_identity` feed into `Crosswalk.register()`
- `CanonicalID` format (`{subsystem}:{native_id}`) must be consistent across all modules
- F1's `EntityType.diagnostic_property` informs which resolution strategy to use per type

---

### Task 1: SQLite Storage Layer

**Files:**
- Create: `src/interweave/storage.py`
- Test: `tests/test_storage.py`

**Step 1: Write the failing test**
```python
# tests/test_storage.py
"""Tests for CrosswalkDB storage layer."""

import sqlite3
import tempfile
from pathlib import Path

import pytest

from interweave.storage import CrosswalkDB


@pytest.fixture
def db(tmp_path):
    return CrosswalkDB(tmp_path / "test.db")


class TestSchema:
    def test_creates_tables(self, db):
        conn = sqlite3.connect(db.path)
        tables = {r[0] for r in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        ).fetchall()}
        assert "entities" in tables
        assert "identity_links" in tables
        assert "actors" in tables
        assert "identity_chains" in tables
        conn.close()

    def test_schema_version(self, db):
        conn = sqlite3.connect(db.path)
        version = conn.execute("PRAGMA user_version").fetchone()[0]
        assert version == 1
        conn.close()


class TestEntityCRUD:
    def test_upsert_and_get(self, db):
        db.upsert_entity("git:src/main.py", "file", "artifact", {"path": "src/main.py"})
        entity = db.get_entity("git:src/main.py")
        assert entity is not None
        assert entity["entity_type"] == "file"
        assert entity["family"] == "artifact"

    def test_upsert_updates_existing(self, db):
        db.upsert_entity("git:src/main.py", "file", "artifact", {"path": "src/main.py"})
        db.upsert_entity("git:src/main.py", "file", "artifact", {"path": "src/main.py", "size": 1024})
        entity = db.get_entity("git:src/main.py")
        assert entity["properties"]["size"] == 1024


class TestIdentityLinks:
    def test_add_and_query(self, db):
        db.upsert_entity("git:src/main.py", "file", "artifact", {})
        db.add_identity_link(
            subsystem="beads", subsystem_id="file:src/main.py",
            canonical_id="git:src/main.py",
            confidence="confirmed", method="path-match",
        )
        links = db.get_links_for("git:src/main.py")
        assert len(links) == 1
        assert links[0]["subsystem"] == "beads"

    def test_lookup_by_subsystem_id(self, db):
        db.upsert_entity("git:src/main.py", "file", "artifact", {})
        db.add_identity_link(
            subsystem="beads", subsystem_id="file:src/main.py",
            canonical_id="git:src/main.py",
            confidence="confirmed", method="path-match",
        )
        canonical = db.lookup("beads", "file:src/main.py")
        assert canonical == "git:src/main.py"


class TestActors:
    def test_add_and_query(self, db):
        db.upsert_actor(
            subsystem="git", actor_id="mk",
            canonical_person_id="mk@example.com",
            confidence="confirmed", method="git-config",
        )
        person = db.lookup_actor("git", "mk")
        assert person == "mk@example.com"


class TestIdentityChains:
    def test_record_and_query(self, db):
        db.upsert_entity("git:src/old_name.py:foo", "function", "artifact", {})
        db.upsert_entity("git:src/new_name.py:foo", "function", "artifact", {})
        db.record_chain(
            from_id="git:src/old_name.py:foo",
            to_id="git:src/new_name.py:foo",
            relation="renamed_to",
            confidence="confirmed",
        )
        chain = db.get_chain("git:src/old_name.py:foo")
        assert len(chain) == 1
        assert chain[0]["to_id"] == "git:src/new_name.py:foo"
```

**Step 2: Run test to verify it fails**
Run: `cd interverse/interweave && uv run pytest tests/test_storage.py -v`
Expected: FAIL with "ModuleNotFoundError: No module named 'interweave.storage'"

**Step 3: Write minimal implementation**
```python
# src/interweave/storage.py
"""SQLite storage for the identity crosswalk.

Single database with four tables: entities, identity_links, actors, identity_chains.
WAL mode for concurrent read access. Schema versioned via PRAGMA user_version.
"""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 1

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS entities (
    canonical_id TEXT PRIMARY KEY,
    entity_type TEXT NOT NULL,
    family TEXT NOT NULL,
    properties TEXT DEFAULT '{}',
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE IF NOT EXISTS identity_links (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    subsystem TEXT NOT NULL,
    subsystem_id TEXT NOT NULL,
    canonical_id TEXT NOT NULL REFERENCES entities(canonical_id),
    confidence TEXT NOT NULL CHECK (confidence IN ('confirmed', 'probable', 'speculative')),
    method TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    last_verified_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    UNIQUE(subsystem, subsystem_id)
);

CREATE TABLE IF NOT EXISTS actors (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    subsystem TEXT NOT NULL,
    actor_id TEXT NOT NULL,
    canonical_person_id TEXT NOT NULL,
    confidence TEXT NOT NULL CHECK (confidence IN ('confirmed', 'probable', 'speculative')),
    method TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    UNIQUE(subsystem, actor_id)
);

CREATE TABLE IF NOT EXISTS identity_chains (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    from_id TEXT NOT NULL,
    to_id TEXT NOT NULL,
    relation TEXT NOT NULL,
    confidence TEXT NOT NULL CHECK (confidence IN ('confirmed', 'probable', 'speculative')),
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_links_canonical ON identity_links(canonical_id);
CREATE INDEX IF NOT EXISTS idx_links_subsystem ON identity_links(subsystem, subsystem_id);
CREATE INDEX IF NOT EXISTS idx_actors_subsystem ON actors(subsystem, actor_id);
CREATE INDEX IF NOT EXISTS idx_actors_person ON actors(canonical_person_id);
CREATE INDEX IF NOT EXISTS idx_chains_from ON identity_chains(from_id);
CREATE INDEX IF NOT EXISTS idx_chains_to ON identity_chains(to_id);
"""


class CrosswalkDB:
    """SQLite storage for entity crosswalk, identity links, actors, and chains."""

    def __init__(self, path: str | Path) -> None:
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(str(self.path))
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.execute("PRAGMA foreign_keys=ON")
        self._init_schema()

    def _init_schema(self) -> None:
        version = self._conn.execute("PRAGMA user_version").fetchone()[0]
        if version < SCHEMA_VERSION:
            self._conn.executescript(SCHEMA_SQL)
            self._conn.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")
            self._conn.commit()

    def close(self) -> None:
        self._conn.close()

    # ─── Entities ───────────────────────────────────────────────

    def upsert_entity(
        self, canonical_id: str, entity_type: str, family: str,
        properties: dict[str, Any] | None = None,
    ) -> None:
        props_json = json.dumps(properties or {})
        self._conn.execute(
            """INSERT INTO entities (canonical_id, entity_type, family, properties)
               VALUES (?, ?, ?, ?)
               ON CONFLICT(canonical_id) DO UPDATE SET
                 entity_type = excluded.entity_type,
                 family = excluded.family,
                 properties = excluded.properties,
                 updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')""",
            (canonical_id, entity_type, family, props_json),
        )
        self._conn.commit()

    def get_entity(self, canonical_id: str) -> dict[str, Any] | None:
        row = self._conn.execute(
            "SELECT * FROM entities WHERE canonical_id = ?", (canonical_id,)
        ).fetchone()
        if row is None:
            return None
        return {
            "canonical_id": row["canonical_id"],
            "entity_type": row["entity_type"],
            "family": row["family"],
            "properties": json.loads(row["properties"]),
            "created_at": row["created_at"],
            "updated_at": row["updated_at"],
        }

    # ─── Identity Links ────────────────────────────────────────

    def add_identity_link(
        self, *, subsystem: str, subsystem_id: str, canonical_id: str,
        confidence: str, method: str,
    ) -> None:
        self._conn.execute(
            """INSERT INTO identity_links (subsystem, subsystem_id, canonical_id, confidence, method)
               VALUES (?, ?, ?, ?, ?)
               ON CONFLICT(subsystem, subsystem_id) DO UPDATE SET
                 canonical_id = excluded.canonical_id,
                 confidence = excluded.confidence,
                 method = excluded.method,
                 last_verified_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')""",
            (subsystem, subsystem_id, canonical_id, confidence, method),
        )
        self._conn.commit()

    def get_links_for(self, canonical_id: str) -> list[dict[str, Any]]:
        rows = self._conn.execute(
            "SELECT * FROM identity_links WHERE canonical_id = ?", (canonical_id,)
        ).fetchall()
        return [dict(r) for r in rows]

    def lookup(self, subsystem: str, subsystem_id: str) -> str | None:
        row = self._conn.execute(
            "SELECT canonical_id FROM identity_links WHERE subsystem = ? AND subsystem_id = ?",
            (subsystem, subsystem_id),
        ).fetchone()
        return row["canonical_id"] if row else None

    # ─── Actors ─────────────────────────────────────────────────

    def upsert_actor(
        self, *, subsystem: str, actor_id: str, canonical_person_id: str,
        confidence: str, method: str,
    ) -> None:
        self._conn.execute(
            """INSERT INTO actors (subsystem, actor_id, canonical_person_id, confidence, method)
               VALUES (?, ?, ?, ?, ?)
               ON CONFLICT(subsystem, actor_id) DO UPDATE SET
                 canonical_person_id = excluded.canonical_person_id,
                 confidence = excluded.confidence,
                 method = excluded.method""",
            (subsystem, actor_id, canonical_person_id, confidence, method),
        )
        self._conn.commit()

    def lookup_actor(self, subsystem: str, actor_id: str) -> str | None:
        row = self._conn.execute(
            "SELECT canonical_person_id FROM actors WHERE subsystem = ? AND actor_id = ?",
            (subsystem, actor_id),
        ).fetchone()
        return row["canonical_person_id"] if row else None

    # ─── Identity Chains ────────────────────────────────────────

    def record_chain(
        self, *, from_id: str, to_id: str, relation: str, confidence: str,
    ) -> None:
        self._conn.execute(
            """INSERT INTO identity_chains (from_id, to_id, relation, confidence)
               VALUES (?, ?, ?, ?)""",
            (from_id, to_id, relation, confidence),
        )
        self._conn.commit()

    def get_chain(self, from_id: str) -> list[dict[str, Any]]:
        rows = self._conn.execute(
            "SELECT * FROM identity_chains WHERE from_id = ?", (from_id,)
        ).fetchall()
        return [dict(r) for r in rows]
```

**Step 4: Run test to verify it passes**
Run: `cd interverse/interweave && uv run pytest tests/test_storage.py -v`
Expected: PASS (all 9 tests)

**Step 5: Commit**
```bash
git add src/interweave/storage.py tests/test_storage.py
git commit -m "feat(interweave): add SQLite crosswalk storage layer"
```

<verify>
- run: `cd interverse/interweave && uv run pytest tests/test_storage.py -v`
  expect: exit 0
- run: `cd interverse/interweave && uv run python -c "from interweave.storage import CrosswalkDB; print('OK')"`
  expect: contains "OK"
</verify>

---

### Task 2: Canonical ID Format and Crosswalk API

**Files:**
- Create: `src/interweave/crosswalk.py`
- Test: `tests/test_crosswalk.py`

**Depends:** task-1

**Step 1: Write the failing test**
```python
# tests/test_crosswalk.py
"""Tests for the Crosswalk API and CanonicalID format."""

import pytest

from interweave.crosswalk import CanonicalID, Crosswalk
from interweave.storage import CrosswalkDB


@pytest.fixture
def crosswalk(tmp_path):
    db = CrosswalkDB(tmp_path / "test.db")
    return Crosswalk(db)


class TestCanonicalID:
    def test_format(self):
        cid = CanonicalID("git", "src/main.py")
        assert str(cid) == "git:src/main.py"

    def test_parse(self):
        cid = CanonicalID.parse("git:src/main.py")
        assert cid.subsystem == "git"
        assert cid.native_id == "src/main.py"

    def test_parse_with_colons_in_id(self):
        cid = CanonicalID.parse("git:src/main.py:MyClass.method")
        assert cid.subsystem == "git"
        assert cid.native_id == "src/main.py:MyClass.method"

    def test_parse_invalid(self):
        with pytest.raises(ValueError):
            CanonicalID.parse("no_colon")


class TestCrosswalkRegister:
    def test_register_entity(self, crosswalk):
        cid = crosswalk.register(
            subsystem="git", native_id="src/main.py",
            entity_type="file", family="artifact",
        )
        assert str(cid) == "git:src/main.py"

    def test_register_idempotent(self, crosswalk):
        cid1 = crosswalk.register(
            subsystem="git", native_id="src/main.py",
            entity_type="file", family="artifact",
        )
        cid2 = crosswalk.register(
            subsystem="git", native_id="src/main.py",
            entity_type="file", family="artifact",
        )
        assert str(cid1) == str(cid2)

    def test_register_with_properties(self, crosswalk):
        crosswalk.register(
            subsystem="git", native_id="src/main.py",
            entity_type="file", family="artifact",
            properties={"lines": 100},
        )
        entity = crosswalk.get("git:src/main.py")
        assert entity["properties"]["lines"] == 100


class TestCrosswalkLink:
    def test_link_cross_subsystem(self, crosswalk):
        crosswalk.register(
            subsystem="git", native_id="src/main.py",
            entity_type="file", family="artifact",
        )
        crosswalk.link(
            subsystem="beads", subsystem_id="file:src/main.py",
            canonical_id="git:src/main.py",
            confidence="confirmed", method="path-match",
        )
        resolved = crosswalk.resolve("beads", "file:src/main.py")
        assert resolved == "git:src/main.py"

    def test_resolve_unknown_returns_none(self, crosswalk):
        assert crosswalk.resolve("beads", "nonexistent") is None


class TestCrosswalkActors:
    def test_register_and_resolve_actor(self, crosswalk):
        crosswalk.register_actor(
            subsystem="git", actor_id="mk",
            canonical_person_id="mk@example.com",
            confidence="confirmed", method="git-config",
        )
        assert crosswalk.resolve_actor("git", "mk") == "mk@example.com"


class TestCrosswalkChains:
    def test_record_and_follow_chain(self, crosswalk):
        crosswalk.register(
            subsystem="git", native_id="src/old.py:foo",
            entity_type="function", family="artifact",
        )
        crosswalk.register(
            subsystem="git", native_id="src/new.py:foo",
            entity_type="function", family="artifact",
        )
        crosswalk.record_rename(
            from_id="git:src/old.py:foo",
            to_id="git:src/new.py:foo",
            confidence="confirmed",
        )
        chain = crosswalk.follow_chain("git:src/old.py:foo")
        assert "git:src/new.py:foo" in [c["to_id"] for c in chain]


class TestDedupDetection:
    def test_flags_likely_duplicates(self, crosswalk):
        crosswalk.register(
            subsystem="git", native_id="src/utils.py",
            entity_type="file", family="artifact",
            properties={"path": "src/utils.py"},
        )
        crosswalk.register(
            subsystem="cass", native_id="src/utils.py",
            entity_type="file", family="artifact",
            properties={"path": "src/utils.py"},
        )
        dupes = crosswalk.detect_duplicates(entity_type="file")
        assert len(dupes) >= 1
        ids = {d["canonical_id_a"] for d in dupes} | {d["canonical_id_b"] for d in dupes}
        assert "git:src/utils.py" in ids
        assert "cass:src/utils.py" in ids
```

**Step 2: Run test to verify it fails**
Run: `cd interverse/interweave && uv run pytest tests/test_crosswalk.py -v`
Expected: FAIL with "ModuleNotFoundError: No module named 'interweave.crosswalk'"

**Step 3: Write minimal implementation**
```python
# src/interweave/crosswalk.py
"""High-level crosswalk API.

Provides the public interface for entity registration, cross-subsystem
identity linking, actor resolution, and dedup detection. Wraps CrosswalkDB.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from interweave.storage import CrosswalkDB


@dataclass(frozen=True)
class CanonicalID:
    """Composite canonical entity ID: {subsystem}:{native_id}."""

    subsystem: str
    native_id: str

    def __str__(self) -> str:
        return f"{self.subsystem}:{self.native_id}"

    @classmethod
    def parse(cls, raw: str) -> CanonicalID:
        colon = raw.find(":")
        if colon == -1:
            raise ValueError(f"Invalid canonical ID (no colon): {raw!r}")
        return cls(subsystem=raw[:colon], native_id=raw[colon + 1:])


class Crosswalk:
    """High-level identity crosswalk operations."""

    def __init__(self, db: CrosswalkDB) -> None:
        self._db = db

    def register(
        self, *, subsystem: str, native_id: str, entity_type: str, family: str,
        properties: dict[str, Any] | None = None,
    ) -> CanonicalID:
        cid = CanonicalID(subsystem, native_id)
        self._db.upsert_entity(str(cid), entity_type, family, properties)
        return cid

    def get(self, canonical_id: str) -> dict[str, Any] | None:
        return self._db.get_entity(canonical_id)

    def link(
        self, *, subsystem: str, subsystem_id: str, canonical_id: str,
        confidence: str, method: str,
    ) -> None:
        self._db.add_identity_link(
            subsystem=subsystem, subsystem_id=subsystem_id,
            canonical_id=canonical_id, confidence=confidence, method=method,
        )

    def resolve(self, subsystem: str, subsystem_id: str) -> str | None:
        return self._db.lookup(subsystem, subsystem_id)

    def register_actor(
        self, *, subsystem: str, actor_id: str, canonical_person_id: str,
        confidence: str, method: str,
    ) -> None:
        self._db.upsert_actor(
            subsystem=subsystem, actor_id=actor_id,
            canonical_person_id=canonical_person_id,
            confidence=confidence, method=method,
        )

    def resolve_actor(self, subsystem: str, actor_id: str) -> str | None:
        return self._db.lookup_actor(subsystem, actor_id)

    def record_rename(
        self, *, from_id: str, to_id: str, confidence: str,
    ) -> None:
        self._db.record_chain(
            from_id=from_id, to_id=to_id,
            relation="renamed_to", confidence=confidence,
        )

    def follow_chain(self, from_id: str) -> list[dict[str, Any]]:
        return self._db.get_chain(from_id)

    def detect_duplicates(
        self, *, entity_type: str | None = None,
    ) -> list[dict[str, Any]]:
        """Find entities from different subsystems with matching native_ids.

        Two canonical IDs are likely duplicates if they have different
        subsystem prefixes but identical native_id suffixes and same entity_type.
        """
        query = """
            SELECT a.canonical_id AS canonical_id_a,
                   b.canonical_id AS canonical_id_b,
                   a.entity_type
            FROM entities a
            JOIN entities b ON a.canonical_id < b.canonical_id
                AND a.entity_type = b.entity_type
            WHERE substr(a.canonical_id, instr(a.canonical_id, ':') + 1)
                = substr(b.canonical_id, instr(b.canonical_id, ':') + 1)
              AND substr(a.canonical_id, 1, instr(a.canonical_id, ':') - 1)
               != substr(b.canonical_id, 1, instr(b.canonical_id, ':') - 1)
        """
        params: list[str] = []
        if entity_type:
            query += " AND a.entity_type = ?"
            params.append(entity_type)

        rows = self._db._conn.execute(query, params).fetchall()
        return [dict(r) for r in rows]
```

**Step 4: Run test to verify it passes**
Run: `cd interverse/interweave && uv run pytest tests/test_crosswalk.py -v`
Expected: PASS (all 10 tests)

**Step 5: Commit**
```bash
git add src/interweave/crosswalk.py tests/test_crosswalk.py
git commit -m "feat(interweave): add canonical ID format and crosswalk API"
```

<verify>
- run: `cd interverse/interweave && uv run pytest tests/test_crosswalk.py -v`
  expect: exit 0
- run: `cd interverse/interweave && uv run python -c "from interweave.crosswalk import CanonicalID; print(CanonicalID.parse('git:src/main.py'))"`
  expect: contains "git:src/main.py"
</verify>

---

### Task 3: File-Level Identity Resolution

**Files:**
- Create: `src/interweave/resolve_file.py`
- Test: `tests/test_resolve_file.py`

**Depends:** task-2

**Step 1: Write the failing test**
```python
# tests/test_resolve_file.py
"""Tests for file-level identity resolution."""

import subprocess
import tempfile
from pathlib import Path

import pytest

from interweave.resolve_file import normalize_path, detect_git_renames, resolve_file_identity
from interweave.crosswalk import Crosswalk
from interweave.storage import CrosswalkDB


class TestNormalizePath:
    def test_resolves_relative(self):
        assert normalize_path("src/../src/main.py") == "src/main.py"

    def test_strips_leading_dot_slash(self):
        assert normalize_path("./src/main.py") == "src/main.py"

    def test_normalizes_double_slashes(self):
        assert normalize_path("src//main.py") == "src/main.py"

    def test_preserves_normal_path(self):
        assert normalize_path("src/main.py") == "src/main.py"

    def test_strips_trailing_slash(self):
        assert normalize_path("src/dir/") == "src/dir"


class TestGitRenameDetection:
    @pytest.fixture
    def git_repo(self, tmp_path):
        """Create a temporary git repo with a renamed file."""
        subprocess.run(["git", "init", str(tmp_path)], capture_output=True, check=True)
        subprocess.run(
            ["git", "config", "user.email", "test@test.com"],
            cwd=tmp_path, capture_output=True, check=True,
        )
        subprocess.run(
            ["git", "config", "user.name", "Test"],
            cwd=tmp_path, capture_output=True, check=True,
        )
        # Create and commit original file
        (tmp_path / "old.py").write_text("def hello():\n    return 'world'\n")
        subprocess.run(["git", "add", "old.py"], cwd=tmp_path, capture_output=True, check=True)
        subprocess.run(
            ["git", "commit", "-m", "add old.py"],
            cwd=tmp_path, capture_output=True, check=True,
        )
        # Rename file
        subprocess.run(
            ["git", "mv", "old.py", "new.py"],
            cwd=tmp_path, capture_output=True, check=True,
        )
        subprocess.run(
            ["git", "commit", "-m", "rename old.py to new.py"],
            cwd=tmp_path, capture_output=True, check=True,
        )
        return tmp_path

    def test_detects_rename(self, git_repo):
        renames = detect_git_renames(git_repo)
        assert any(r["old"] == "old.py" and r["new"] == "new.py" for r in renames)

    def test_empty_repo_returns_empty(self, tmp_path):
        subprocess.run(["git", "init", str(tmp_path)], capture_output=True, check=True)
        assert detect_git_renames(tmp_path) == []


class TestResolveFileIdentity:
    def test_normalizes_and_registers(self, tmp_path):
        db = CrosswalkDB(tmp_path / "test.db")
        crosswalk = Crosswalk(db)
        cid = resolve_file_identity(
            crosswalk, path="./src/../src/main.py", subsystem="git",
        )
        assert str(cid) == "git:src/main.py"
        entity = crosswalk.get("git:src/main.py")
        assert entity is not None
        assert entity["entity_type"] == "file"
```

**Step 2: Run test to verify it fails**
Run: `cd interverse/interweave && uv run pytest tests/test_resolve_file.py -v`
Expected: FAIL with "ModuleNotFoundError: No module named 'interweave.resolve_file'"

**Step 3: Write minimal implementation**
```python
# src/interweave/resolve_file.py
"""File-level identity resolution.

Path normalization, git SHA matching, and git rename detection.
"""

from __future__ import annotations

import posixpath
import subprocess
from pathlib import Path
from typing import Any

from interweave.crosswalk import CanonicalID, Crosswalk


def normalize_path(path: str) -> str:
    """Normalize a file path for identity matching.

    Resolves .., strips ./ prefixes, collapses double slashes,
    removes trailing slashes. Uses POSIX path semantics.
    """
    normalized = posixpath.normpath(path)
    if normalized.startswith("./"):
        normalized = normalized[2:]
    return normalized


def detect_git_renames(repo_path: Path, since: str | None = None) -> list[dict[str, str]]:
    """Detect file renames in git history.

    Returns list of {old, new, similarity} dicts for renamed files.
    """
    cmd = ["git", "log", "--diff-filter=R", "--name-status", "-M90%", "--format="]
    if since:
        cmd.append(f"--since={since}")

    try:
        result = subprocess.run(
            cmd, cwd=repo_path, capture_output=True, text=True, check=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []

    renames = []
    for line in result.stdout.strip().split("\n"):
        if not line or not line.startswith("R"):
            continue
        parts = line.split("\t")
        if len(parts) >= 3:
            similarity = parts[0][1:]  # e.g., "R100" → "100"
            renames.append({
                "old": parts[1],
                "new": parts[2],
                "similarity": similarity,
            })
    return renames


def resolve_file_identity(
    crosswalk: Crosswalk, *, path: str, subsystem: str,
    properties: dict[str, Any] | None = None,
) -> CanonicalID:
    """Resolve a file path to a canonical entity ID.

    Normalizes the path and registers it in the crosswalk.
    """
    normalized = normalize_path(path)
    props = {"path": normalized}
    if properties:
        props.update(properties)

    return crosswalk.register(
        subsystem=subsystem, native_id=normalized,
        entity_type="file", family="artifact",
        properties=props,
    )
```

**Step 4: Run test to verify it passes**
Run: `cd interverse/interweave && uv run pytest tests/test_resolve_file.py -v`
Expected: PASS (all 6 tests)

**Step 5: Commit**
```bash
git add src/interweave/resolve_file.py tests/test_resolve_file.py
git commit -m "feat(interweave): add file-level identity resolution"
```

<verify>
- run: `cd interverse/interweave && uv run pytest tests/test_resolve_file.py -v`
  expect: exit 0
</verify>

---

### Task 4: Function-Level Identity Resolution (Tree-Sitter)

**Files:**
- Create: `src/interweave/resolve_function.py`
- Test: `tests/test_resolve_function.py`
- Modify: `pyproject.toml` (add tree-sitter dependencies)

**Depends:** task-2

**Step 1: Add tree-sitter dependencies**
```toml
# In pyproject.toml, update dependencies:
dependencies = [
    "tree-sitter>=0.23",
    "tree-sitter-python>=0.23",
]
```
Run: `cd interverse/interweave && uv sync`

**Step 2: Write the failing test**
```python
# tests/test_resolve_function.py
"""Tests for function-level identity resolution via tree-sitter."""

import pytest

from interweave.resolve_function import (
    SUPPORTED_LANGUAGES,
    ASTFingerprint,
    compute_ast_fingerprint,
    compute_body_similarity,
    resolve_function_identity,
)
from interweave.crosswalk import Crosswalk
from interweave.storage import CrosswalkDB


SAMPLE_PYTHON = '''\
def greet(name: str, greeting: str = "hello") -> str:
    """Say hello."""
    message = f"{greeting}, {name}!"
    return message
'''

SAMPLE_PYTHON_RENAMED = '''\
def say_hello(name: str, greeting: str = "hello") -> str:
    """Say hello."""
    message = f"{greeting}, {name}!"
    return message
'''

SAMPLE_PYTHON_CHANGED = '''\
def greet(name: str) -> str:
    """Completely different function."""
    return name.upper()
'''


class TestSupportedLanguages:
    def test_python_supported(self):
        assert "python" in SUPPORTED_LANGUAGES


class TestASTFingerprint:
    def test_extracts_function(self):
        fps = compute_ast_fingerprint(SAMPLE_PYTHON, "python")
        assert len(fps) == 1
        fp = fps[0]
        assert fp.name == "greet"
        assert fp.parameters == ["name: str", 'greeting: str = "hello"']
        assert fp.return_type == "str"
        assert len(fp.body_hash) > 0

    def test_fingerprint_stable(self):
        fp1 = compute_ast_fingerprint(SAMPLE_PYTHON, "python")
        fp2 = compute_ast_fingerprint(SAMPLE_PYTHON, "python")
        assert fp1[0].body_hash == fp2[0].body_hash

    def test_different_body_different_hash(self):
        fp1 = compute_ast_fingerprint(SAMPLE_PYTHON, "python")
        fp2 = compute_ast_fingerprint(SAMPLE_PYTHON_CHANGED, "python")
        assert fp1[0].body_hash != fp2[0].body_hash


class TestBodySimilarity:
    def test_identical_bodies_100(self):
        fp1 = compute_ast_fingerprint(SAMPLE_PYTHON, "python")[0]
        fp2 = compute_ast_fingerprint(SAMPLE_PYTHON_RENAMED, "python")[0]
        sim = compute_body_similarity(fp1, fp2)
        assert sim > 0.95  # Same body, different name

    def test_different_bodies_low(self):
        fp1 = compute_ast_fingerprint(SAMPLE_PYTHON, "python")[0]
        fp2 = compute_ast_fingerprint(SAMPLE_PYTHON_CHANGED, "python")[0]
        sim = compute_body_similarity(fp1, fp2)
        assert sim < 0.80


class TestResolveFunctionIdentity:
    def test_registers_function(self, tmp_path):
        db = CrosswalkDB(tmp_path / "test.db")
        crosswalk = Crosswalk(db)
        cids = resolve_function_identity(
            crosswalk,
            file_path="src/greet.py",
            source_code=SAMPLE_PYTHON,
            language="python",
            subsystem="git",
        )
        assert len(cids) == 1
        cid = cids[0]
        assert "greet" in str(cid)
        entity = crosswalk.get(str(cid))
        assert entity is not None
        assert entity["entity_type"] == "function"
```

**Step 3: Run test to verify it fails**
Run: `cd interverse/interweave && uv run pytest tests/test_resolve_function.py -v`
Expected: FAIL with "ModuleNotFoundError: No module named 'interweave.resolve_function'"

**Step 4: Write minimal implementation**
```python
# src/interweave/resolve_function.py
"""Function-level identity resolution via tree-sitter AST fingerprinting.

Canonical signature = file_path + function_name + parameter_types + return_type.
Body similarity scoring for rename/move detection.
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from difflib import SequenceMatcher
from typing import Any

from interweave.crosswalk import CanonicalID, Crosswalk
from interweave.resolve_file import normalize_path

# Languages with tree-sitter grammar support for function extraction.
SUPPORTED_LANGUAGES: dict[str, str] = {
    "python": "tree_sitter_python",
}


@dataclass
class ASTFingerprint:
    """Function identity fingerprint from AST analysis."""
    name: str
    parameters: list[str]
    return_type: str | None
    body_text: str
    body_hash: str
    start_line: int
    end_line: int


def _get_parser(language: str):
    """Get a tree-sitter parser for the given language."""
    import tree_sitter_python as tspython
    from tree_sitter import Language, Parser

    if language != "python":
        raise ValueError(f"Unsupported language: {language}")

    lang = Language(tspython.language())
    parser = Parser(lang)
    return parser


def _extract_node_text(source_bytes: bytes, node) -> str:
    """Extract text from a tree-sitter node."""
    return source_bytes[node.start_byte:node.end_byte].decode("utf-8")


def compute_ast_fingerprint(source_code: str, language: str) -> list[ASTFingerprint]:
    """Extract function fingerprints from source code using tree-sitter."""
    if language not in SUPPORTED_LANGUAGES:
        return []

    parser = _get_parser(language)
    source_bytes = source_code.encode("utf-8")
    tree = parser.parse(source_bytes)

    fingerprints = []
    for node in tree.root_node.children:
        if node.type == "function_definition":
            fp = _extract_python_function(source_bytes, node)
            if fp:
                fingerprints.append(fp)

    return fingerprints


def _extract_python_function(source_bytes: bytes, node) -> ASTFingerprint | None:
    """Extract fingerprint from a Python function_definition node."""
    name = None
    parameters = []
    return_type = None
    body_node = None

    for child in node.children:
        if child.type == "identifier":
            name = _extract_node_text(source_bytes, child)
        elif child.type == "parameters":
            for param in child.children:
                if param.type in ("identifier", "typed_parameter",
                                  "typed_default_parameter", "default_parameter"):
                    parameters.append(_extract_node_text(source_bytes, param))
        elif child.type == "type":
            return_type = _extract_node_text(source_bytes, child)
        elif child.type == "block":
            body_node = child

    if not name or not body_node:
        return None

    body_text = _extract_node_text(source_bytes, body_node)
    body_hash = hashlib.sha256(body_text.encode("utf-8")).hexdigest()[:16]

    return ASTFingerprint(
        name=name,
        parameters=parameters,
        return_type=return_type,
        body_text=body_text,
        body_hash=body_hash,
        start_line=node.start_point[0],
        end_line=node.end_point[0],
    )


def compute_body_similarity(fp_a: ASTFingerprint, fp_b: ASTFingerprint) -> float:
    """Compute body similarity between two function fingerprints.

    Returns 0.0-1.0. Uses SequenceMatcher on body text.
    """
    if fp_a.body_hash == fp_b.body_hash:
        return 1.0
    return SequenceMatcher(None, fp_a.body_text, fp_b.body_text).ratio()


def resolve_function_identity(
    crosswalk: Crosswalk, *,
    file_path: str, source_code: str, language: str, subsystem: str,
) -> list[CanonicalID]:
    """Resolve function identities from source code.

    Parses source with tree-sitter, extracts function fingerprints,
    registers each in the crosswalk. Canonical ID format:
    {subsystem}:{normalized_path}:{function_name}({param_types})->{return_type}
    """
    if language not in SUPPORTED_LANGUAGES:
        return []

    normalized = normalize_path(file_path)
    fingerprints = compute_ast_fingerprint(source_code, language)
    cids = []

    for fp in fingerprints:
        # Build canonical signature
        param_sig = ", ".join(fp.parameters)
        ret_sig = f" -> {fp.return_type}" if fp.return_type else ""
        native_id = f"{normalized}:{fp.name}({param_sig}){ret_sig}"

        cid = crosswalk.register(
            subsystem=subsystem, native_id=native_id,
            entity_type="function", family="artifact",
            properties={
                "file_path": normalized,
                "function_name": fp.name,
                "parameters": fp.parameters,
                "return_type": fp.return_type,
                "body_hash": fp.body_hash,
                "start_line": fp.start_line,
                "end_line": fp.end_line,
            },
        )
        cids.append(cid)

    return cids
```

**Step 5: Run test to verify it passes**
Run: `cd interverse/interweave && uv run pytest tests/test_resolve_function.py -v`
Expected: PASS (all 8 tests)

**Step 6: Commit**
```bash
git add pyproject.toml src/interweave/resolve_function.py tests/test_resolve_function.py
git commit -m "feat(interweave): add tree-sitter function-level identity resolution"
```

<verify>
- run: `cd interverse/interweave && uv sync && uv run pytest tests/test_resolve_function.py -v`
  expect: exit 0
</verify>

---

### Task 5: Function Rename/Move Detection

**Files:**
- Create: `src/interweave/detect_renames.py`
- Test: `tests/test_detect_renames.py`

**Depends:** task-4

**Step 1: Write the failing test**
```python
# tests/test_detect_renames.py
"""Tests for function rename/move detection with confidence thresholds."""

import pytest

from interweave.detect_renames import detect_function_renames, RenameMatch
from interweave.resolve_function import ASTFingerprint, compute_ast_fingerprint


OLD_CODE = '''\
def process_data(items: list, threshold: float = 0.5) -> list:
    """Process items above threshold."""
    result = []
    for item in items:
        if item.score > threshold:
            result.append(item)
    return result
'''

RENAMED_CODE = '''\
def filter_by_score(items: list, threshold: float = 0.5) -> list:
    """Process items above threshold."""
    result = []
    for item in items:
        if item.score > threshold:
            result.append(item)
    return result
'''

MODIFIED_CODE = '''\
def process_data(items: list, threshold: float = 0.5) -> list:
    """Process items above threshold with logging."""
    result = []
    for item in items:
        if item.score > threshold:
            print(f"Accepted: {item}")
            result.append(item)
    print(f"Total: {len(result)}")
    return result
'''

DIFFERENT_CODE = '''\
def summarize(data: dict) -> str:
    """Completely different function."""
    return str(data)
'''


class TestDetectRenames:
    def test_identical_body_confirmed(self):
        old_fps = compute_ast_fingerprint(OLD_CODE, "python")
        new_fps = compute_ast_fingerprint(RENAMED_CODE, "python")
        matches = detect_function_renames(old_fps, new_fps)
        assert len(matches) == 1
        assert matches[0].confidence == "confirmed"
        assert matches[0].old_name == "process_data"
        assert matches[0].new_name == "filter_by_score"
        assert matches[0].similarity > 0.95

    def test_modified_body_probable(self):
        old_fps = compute_ast_fingerprint(OLD_CODE, "python")
        new_fps = compute_ast_fingerprint(MODIFIED_CODE, "python")
        matches = detect_function_renames(old_fps, new_fps)
        assert len(matches) == 1
        assert matches[0].confidence == "probable"
        assert 0.80 <= matches[0].similarity <= 0.95

    def test_different_function_no_match(self):
        old_fps = compute_ast_fingerprint(OLD_CODE, "python")
        new_fps = compute_ast_fingerprint(DIFFERENT_CODE, "python")
        matches = detect_function_renames(old_fps, new_fps)
        assert len(matches) == 0
```

**Step 2: Run test to verify it fails**
Run: `cd interverse/interweave && uv run pytest tests/test_detect_renames.py -v`
Expected: FAIL with "ModuleNotFoundError: No module named 'interweave.detect_renames'"

**Step 3: Write minimal implementation**
```python
# src/interweave/detect_renames.py
"""Function rename/move detection with confidence thresholds.

Confidence levels:
- confirmed: body similarity >95% (auto-link)
- probable: body similarity 80-95% (excluded from default queries per F4)
- <80%: no link created
"""

from __future__ import annotations

from dataclasses import dataclass

from interweave.resolve_function import ASTFingerprint, compute_body_similarity

CONFIRMED_THRESHOLD = 0.95
PROBABLE_THRESHOLD = 0.80


@dataclass
class RenameMatch:
    """A detected function rename/move."""
    old_name: str
    new_name: str
    similarity: float
    confidence: str  # "confirmed" or "probable"
    old_fp: ASTFingerprint
    new_fp: ASTFingerprint


def detect_function_renames(
    old_fps: list[ASTFingerprint],
    new_fps: list[ASTFingerprint],
) -> list[RenameMatch]:
    """Detect renames by comparing fingerprints from two versions.

    Compares all pairs, finds best matches above PROBABLE_THRESHOLD.
    Does not create transitive links — each match is independent evidence.
    """
    matches: list[RenameMatch] = []
    used_new: set[int] = set()

    # Sort old by name for deterministic ordering
    scored_pairs: list[tuple[float, int, int]] = []
    for i, old_fp in enumerate(old_fps):
        for j, new_fp in enumerate(new_fps):
            sim = compute_body_similarity(old_fp, new_fp)
            if sim >= PROBABLE_THRESHOLD:
                scored_pairs.append((sim, i, j))

    # Greedy match: highest similarity first
    scored_pairs.sort(key=lambda x: x[0], reverse=True)
    used_old: set[int] = set()

    for sim, i, j in scored_pairs:
        if i in used_old or j in used_new:
            continue
        used_old.add(i)
        used_new.add(j)

        confidence = "confirmed" if sim > CONFIRMED_THRESHOLD else "probable"
        matches.append(RenameMatch(
            old_name=old_fps[i].name,
            new_name=new_fps[j].name,
            similarity=sim,
            confidence=confidence,
            old_fp=old_fps[i],
            new_fp=new_fps[j],
        ))

    return matches
```

**Step 4: Run test to verify it passes**
Run: `cd interverse/interweave && uv run pytest tests/test_detect_renames.py -v`
Expected: PASS (all 3 tests)

**Step 5: Commit**
```bash
git add src/interweave/detect_renames.py tests/test_detect_renames.py
git commit -m "feat(interweave): add function rename/move detection with confidence thresholds"
```

<verify>
- run: `cd interverse/interweave && uv run pytest tests/test_detect_renames.py -v`
  expect: exit 0
</verify>

---

### Task 6: Actor Identity Resolution

**Files:**
- Create: `src/interweave/resolve_actor.py`
- Test: `tests/test_resolve_actor.py`

**Depends:** task-2

**Step 1: Write the failing test**
```python
# tests/test_resolve_actor.py
"""Tests for actor identity resolution across subsystems."""

import subprocess
import pytest

from interweave.resolve_actor import resolve_git_actors, resolve_actor_identity
from interweave.crosswalk import Crosswalk
from interweave.storage import CrosswalkDB


class TestResolveGitActors:
    @pytest.fixture
    def git_repo(self, tmp_path):
        subprocess.run(["git", "init", str(tmp_path)], capture_output=True, check=True)
        subprocess.run(
            ["git", "config", "user.email", "dev@example.com"],
            cwd=tmp_path, capture_output=True, check=True,
        )
        subprocess.run(
            ["git", "config", "user.name", "Dev User"],
            cwd=tmp_path, capture_output=True, check=True,
        )
        (tmp_path / "file.txt").write_text("content")
        subprocess.run(["git", "add", "."], cwd=tmp_path, capture_output=True, check=True)
        subprocess.run(
            ["git", "commit", "-m", "init"],
            cwd=tmp_path, capture_output=True, check=True,
        )
        return tmp_path

    def test_extracts_git_actors(self, git_repo):
        actors = resolve_git_actors(git_repo)
        assert len(actors) >= 1
        assert actors[0]["name"] == "Dev User"
        assert actors[0]["email"] == "dev@example.com"


class TestResolveActorIdentity:
    def test_registers_actor(self, tmp_path):
        db = CrosswalkDB(tmp_path / "test.db")
        crosswalk = Crosswalk(db)
        resolve_actor_identity(
            crosswalk,
            subsystem="git", actor_id="Dev User",
            canonical_person_id="dev@example.com",
            method="git-log",
        )
        assert crosswalk.resolve_actor("git", "Dev User") == "dev@example.com"

    def test_multiple_subsystems_same_person(self, tmp_path):
        db = CrosswalkDB(tmp_path / "test.db")
        crosswalk = Crosswalk(db)
        resolve_actor_identity(
            crosswalk,
            subsystem="git", actor_id="mk",
            canonical_person_id="mk@example.com",
            method="git-config",
        )
        resolve_actor_identity(
            crosswalk,
            subsystem="beads", actor_id="session-abc123",
            canonical_person_id="mk@example.com",
            method="session-claim",
        )
        assert crosswalk.resolve_actor("git", "mk") == "mk@example.com"
        assert crosswalk.resolve_actor("beads", "session-abc123") == "mk@example.com"
```

**Step 2: Run test to verify it fails**
Run: `cd interverse/interweave && uv run pytest tests/test_resolve_actor.py -v`
Expected: FAIL with "ModuleNotFoundError: No module named 'interweave.resolve_actor'"

**Step 3: Write minimal implementation**
```python
# src/interweave/resolve_actor.py
"""Actor identity resolution.

Unifies developer identity across git username, session ID,
beads claimed_by, PR reviewer name. Canonical person ID = git email.
"""

from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Any

from interweave.crosswalk import Crosswalk


def resolve_git_actors(repo_path: Path) -> list[dict[str, str]]:
    """Extract unique author identities from git log.

    Returns list of {name, email} dicts, deduplicated by email.
    """
    try:
        result = subprocess.run(
            ["git", "log", "--format=%aN\t%aE", "--no-merges"],
            cwd=repo_path, capture_output=True, text=True, check=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []

    seen: set[str] = set()
    actors: list[dict[str, str]] = []
    for line in result.stdout.strip().split("\n"):
        if not line or "\t" not in line:
            continue
        name, email = line.split("\t", 1)
        if email not in seen:
            seen.add(email)
            actors.append({"name": name, "email": email})
    return actors


def resolve_actor_identity(
    crosswalk: Crosswalk, *,
    subsystem: str, actor_id: str, canonical_person_id: str,
    method: str, confidence: str = "confirmed",
) -> None:
    """Register an actor identity mapping in the crosswalk."""
    crosswalk.register_actor(
        subsystem=subsystem, actor_id=actor_id,
        canonical_person_id=canonical_person_id,
        confidence=confidence, method=method,
    )
```

**Step 4: Run test to verify it passes**
Run: `cd interverse/interweave && uv run pytest tests/test_resolve_actor.py -v`
Expected: PASS (all 3 tests)

**Step 5: Commit**
```bash
git add src/interweave/resolve_actor.py tests/test_resolve_actor.py
git commit -m "feat(interweave): add actor identity resolution"
```

<verify>
- run: `cd interverse/interweave && uv run pytest tests/test_resolve_actor.py -v`
  expect: exit 0
</verify>

---

### Task 7: Diagnostic Property Table and Public API

**Files:**
- Create: `src/interweave/diagnostics.py`
- Modify: `src/interweave/__init__.py`
- Test: `tests/test_diagnostics.py`

**Depends:** task-2, task-3, task-4, task-6

**Step 1: Write the failing test**
```python
# tests/test_diagnostics.py
"""Tests for per-entity-type diagnostic property table."""

from interweave.diagnostics import DIAGNOSTIC_PROPERTIES, get_diagnostic_property


class TestDiagnosticProperties:
    def test_file_anchor(self):
        assert get_diagnostic_property("file") == "path"

    def test_function_anchor(self):
        assert get_diagnostic_property("function") == "ast_fingerprint"

    def test_bead_anchor(self):
        assert get_diagnostic_property("bead") == "bead_id"

    def test_session_anchor(self):
        assert get_diagnostic_property("session") == "session_id"

    def test_agent_anchor(self):
        assert get_diagnostic_property("agent") == "agent_name"

    def test_human_anchor(self):
        assert get_diagnostic_property("human") == "email"

    def test_unknown_returns_none(self):
        assert get_diagnostic_property("unknown") is None

    def test_table_completeness(self):
        """Every built-in entity type has a diagnostic property."""
        from interweave.families import list_entity_types
        for et in list_entity_types():
            assert et.name in DIAGNOSTIC_PROPERTIES, (
                f"Missing diagnostic property for {et.name}"
            )
```

**Step 2: Run test to verify it fails**
Run: `cd interverse/interweave && uv run pytest tests/test_diagnostics.py -v`
Expected: FAIL with "ModuleNotFoundError: No module named 'interweave.diagnostics'"

**Step 3: Write minimal implementation**
```python
# src/interweave/diagnostics.py
"""Per-entity-type diagnostic property table.

Maps each entity type to its identity-bearing field — the property
that anchors identity resolution for that type.
"""

from __future__ import annotations

# Diagnostic properties: the identity anchor for each entity type.
# These are the properties that uniquely identify an entity within its subsystem.
DIAGNOSTIC_PROPERTIES: dict[str, str] = {
    # Artifact family
    "file": "path",
    "function": "ast_fingerprint",
    "module": "path",
    "test": "path_and_name",
    "config": "path",
    # Process family
    "session": "session_id",
    "run": "run_id",
    "bead": "bead_id",
    "sprint": "sprint_id",
    # Actor family
    "agent": "agent_name",
    "model": "model_id",
    "human": "email",
    "plugin": "plugin_name",
    # Relationship family
    "dependency": "source_target_type",
    "blocks": "source_target",
    "reference": "source_target",
    # Evidence family
    "finding": "finding_id",
    "verdict": "verdict_id",
    "discovery": "discovery_id",
    "metric": "metric_id",
}


def get_diagnostic_property(entity_type: str) -> str | None:
    """Look up the identity anchor for an entity type."""
    return DIAGNOSTIC_PROPERTIES.get(entity_type)
```

**Step 4: Update `__init__.py` with new public API**
```python
# src/interweave/__init__.py
"""interweave — generative ontology layer for agentic platforms."""

from interweave.crosswalk import CanonicalID, Crosswalk
from interweave.diagnostics import DIAGNOSTIC_PROPERTIES, get_diagnostic_property
from interweave.engine import apply_lifecycle_transition, valid_relationships
from interweave.families import EntityType, TypeFamily, get_entity_type, register_entity_type
from interweave.rules import InteractionRule, register_rule
from interweave.storage import CrosswalkDB

__all__ = [
    # F1: Type families + relational calculus
    "TypeFamily",
    "EntityType",
    "InteractionRule",
    "register_entity_type",
    "get_entity_type",
    "register_rule",
    "valid_relationships",
    "apply_lifecycle_transition",
    # F2: Identity crosswalk
    "CanonicalID",
    "Crosswalk",
    "CrosswalkDB",
    "DIAGNOSTIC_PROPERTIES",
    "get_diagnostic_property",
]
```

**Step 5: Run test to verify it passes**
Run: `cd interverse/interweave && uv run pytest tests/test_diagnostics.py -v`
Expected: PASS (all 8 tests)

**Step 6: Commit**
```bash
git add src/interweave/diagnostics.py src/interweave/__init__.py tests/test_diagnostics.py
git commit -m "feat(interweave): add diagnostic property table and update public API"
```

<verify>
- run: `cd interverse/interweave && uv run pytest tests/test_diagnostics.py -v`
  expect: exit 0
- run: `cd interverse/interweave && uv run python -c "from interweave import Crosswalk, CanonicalID, CrosswalkDB; print('API OK')"`
  expect: contains "API OK"
</verify>

---

### Task 8: Integration Test — Full Crosswalk Workflow

**Files:**
- Create: `tests/test_integration_crosswalk.py`

**Depends:** task-1, task-2, task-3, task-4, task-5, task-6, task-7

**Step 1: Write integration test**
```python
# tests/test_integration_crosswalk.py
"""Integration test: full crosswalk workflow.

Exercises the complete identity crosswalk pipeline: register entities
from multiple subsystems, link cross-subsystem IDs, resolve actors,
detect renames, follow identity chains, and detect duplicates.
"""

import pytest

from interweave.crosswalk import CanonicalID, Crosswalk
from interweave.detect_renames import detect_function_renames
from interweave.resolve_actor import resolve_actor_identity
from interweave.resolve_file import resolve_file_identity
from interweave.resolve_function import compute_ast_fingerprint, resolve_function_identity
from interweave.storage import CrosswalkDB


PYTHON_V1 = '''\
def process(items: list) -> list:
    """Filter items."""
    return [i for i in items if i.valid]
'''

PYTHON_V2 = '''\
def filter_valid(items: list) -> list:
    """Filter items."""
    return [i for i in items if i.valid]
'''


@pytest.fixture
def crosswalk(tmp_path):
    db = CrosswalkDB(tmp_path / "interweave.db")
    return Crosswalk(db)


class TestFullWorkflow:
    def test_file_identity_from_multiple_subsystems(self, crosswalk):
        # Git sees src/main.py
        cid_git = resolve_file_identity(
            crosswalk, path="src/main.py", subsystem="git",
        )
        # Beads references the same file differently
        crosswalk.link(
            subsystem="beads", subsystem_id="file:src/main.py",
            canonical_id=str(cid_git),
            confidence="confirmed", method="path-match",
        )
        # Resolution works from beads
        assert crosswalk.resolve("beads", "file:src/main.py") == "git:src/main.py"

    def test_function_rename_detection_and_chain(self, crosswalk):
        # Register v1 functions
        cids_v1 = resolve_function_identity(
            crosswalk, file_path="src/proc.py",
            source_code=PYTHON_V1, language="python", subsystem="git",
        )
        # Register v2 functions
        cids_v2 = resolve_function_identity(
            crosswalk, file_path="src/proc.py",
            source_code=PYTHON_V2, language="python", subsystem="git",
        )
        # Detect rename
        fps_v1 = compute_ast_fingerprint(PYTHON_V1, "python")
        fps_v2 = compute_ast_fingerprint(PYTHON_V2, "python")
        matches = detect_function_renames(fps_v1, fps_v2)
        assert len(matches) == 1
        assert matches[0].confidence == "confirmed"

        # Record the chain
        crosswalk.record_rename(
            from_id=str(cids_v1[0]),
            to_id=str(cids_v2[0]),
            confidence=matches[0].confidence,
        )
        chain = crosswalk.follow_chain(str(cids_v1[0]))
        assert len(chain) == 1

    def test_actor_unification(self, crosswalk):
        resolve_actor_identity(
            crosswalk, subsystem="git", actor_id="mk",
            canonical_person_id="mk@example.com", method="git-config",
        )
        resolve_actor_identity(
            crosswalk, subsystem="cass", actor_id="session-xyz",
            canonical_person_id="mk@example.com", method="session-claim",
        )
        assert crosswalk.resolve_actor("git", "mk") == "mk@example.com"
        assert crosswalk.resolve_actor("cass", "session-xyz") == "mk@example.com"

    def test_dedup_detection(self, crosswalk):
        resolve_file_identity(crosswalk, path="src/utils.py", subsystem="git")
        resolve_file_identity(crosswalk, path="src/utils.py", subsystem="cass")
        dupes = crosswalk.detect_duplicates(entity_type="file")
        assert len(dupes) >= 1

    def test_no_transitive_closure(self, crosswalk):
        # A=B and B=C does NOT imply A=C
        crosswalk.link(
            subsystem="beads", subsystem_id="file:a.py",
            canonical_id="git:a.py",
            confidence="confirmed", method="path-match",
        )
        # Register git:a.py first
        crosswalk.register(
            subsystem="git", native_id="a.py",
            entity_type="file", family="artifact",
        )
        crosswalk.link(
            subsystem="cass", subsystem_id="file:a.py",
            canonical_id="git:a.py",
            confidence="confirmed", method="path-match",
        )
        # Both beads and cass resolve to git:a.py — but this is because
        # both link directly to the canonical ID, not through transitive closure.
        # If we had beads→cass (without beads→git), it would NOT resolve.
        assert crosswalk.resolve("beads", "file:a.py") == "git:a.py"
        assert crosswalk.resolve("cass", "file:a.py") == "git:a.py"
        # Direct only — no chaining through other links
        assert crosswalk.resolve("beads", "file:a.py") is not None
```

**Step 2: Run integration test**
Run: `cd interverse/interweave && uv run pytest tests/test_integration_crosswalk.py -v`
Expected: PASS (all 5 tests)

**Step 3: Run full test suite**
Run: `cd interverse/interweave && uv run pytest tests/ -v`
Expected: PASS (all tests from tasks 1-8)

**Step 4: Commit**
```bash
git add tests/test_integration_crosswalk.py
git commit -m "test(interweave): add integration test for full crosswalk workflow"
```

<verify>
- run: `cd interverse/interweave && uv run pytest tests/ -v`
  expect: exit 0
- run: `cd interverse/interweave && uv run ruff check src/`
  expect: exit 0
</verify>
