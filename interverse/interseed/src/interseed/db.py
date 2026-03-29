"""SQLite database schema and queries for interseed."""

from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .models import Annotation, Idea, RefinementLog

SCHEMA_VERSION = 1

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS ideas (
    id TEXT PRIMARY KEY,
    thesis TEXT NOT NULL,
    evidence TEXT DEFAULT '[]',
    confidence REAL DEFAULT 0.1,
    maturity TEXT DEFAULT 'seed'
        CHECK (maturity IN ('seed','sprouting','growing','mature')),
    keywords TEXT DEFAULT '[]',
    open_questions TEXT DEFAULT '[]',
    garden_id TEXT,
    source TEXT DEFAULT 'manual',
    graduated_bead_id TEXT,
    enriched BOOLEAN DEFAULT 0,
    locked_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS refinement_log (
    id TEXT PRIMARY KEY,
    idea_id TEXT NOT NULL REFERENCES ideas(id) ON DELETE CASCADE,
    trigger TEXT NOT NULL
        CHECK (trigger IN ('scheduled','event','manual')),
    summary TEXT NOT NULL,
    confidence_before REAL,
    confidence_after REAL,
    new_evidence TEXT DEFAULT '[]',
    context_hash TEXT,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS annotations (
    id TEXT PRIMARY KEY,
    idea_id TEXT NOT NULL REFERENCES ideas(id) ON DELETE CASCADE,
    source TEXT NOT NULL,
    annotation_type TEXT NOT NULL
        CHECK (annotation_type IN ('comment','steer','graduation_approval')),
    body TEXT NOT NULL,
    created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_ideas_maturity ON ideas(maturity);
CREATE INDEX IF NOT EXISTS idx_ideas_enriched ON ideas(enriched) WHERE enriched = 0;
CREATE INDEX IF NOT EXISTS idx_refinement_idea ON refinement_log(idea_id);
CREATE INDEX IF NOT EXISTS idx_annotations_idea ON annotations(idea_id);

CREATE TABLE IF NOT EXISTS schema_info (
    version INTEGER NOT NULL
);
"""


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _ulid() -> str:
    """Generate a short unique ID."""
    import hashlib
    import time

    raw = f"{time.time_ns()}"
    return hashlib.sha256(raw.encode()).hexdigest()[:12]


class InterseedDB:
    def __init__(self, db_path: str | Path):
        self.db_path = Path(db_path).expanduser()
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._conn: sqlite3.Connection | None = None

    @property
    def conn(self) -> sqlite3.Connection:
        if self._conn is None:
            raise RuntimeError("Database not connected. Call connect() first.")
        return self._conn

    def connect(self) -> None:
        self._conn = sqlite3.connect(str(self.db_path))
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.execute("PRAGMA synchronous=NORMAL")
        self._conn.execute("PRAGMA foreign_keys=ON")
        self._init_schema()

    def close(self) -> None:
        if self._conn:
            self._conn.close()
            self._conn = None

    def _init_schema(self) -> None:
        # Use EXCLUSIVE to prevent race on first-run concurrent init
        self.conn.execute("BEGIN EXCLUSIVE")
        try:
            self.conn.executescript(SCHEMA_SQL)
            row = self.conn.execute(
                "SELECT version FROM schema_info LIMIT 1"
            ).fetchone()
            if row is None:
                self.conn.execute(
                    "INSERT OR IGNORE INTO schema_info (version) VALUES (?)",
                    (SCHEMA_VERSION,),
                )
            self.conn.commit()
        except Exception:
            self.conn.rollback()
            raise

    # --- Ideas ---

    def plant_idea(
        self, thesis: str, source: str = "cli", keywords: list[str] | None = None
    ) -> Idea:
        """Insert a new idea with raw text. Returns the created Idea."""
        idea_id = _ulid()
        now = _now_iso()
        kw_json = json.dumps(keywords or [])

        self.conn.execute(
            """INSERT INTO ideas (id, thesis, source, keywords, enriched, created_at, updated_at)
               VALUES (?, ?, ?, ?, 0, ?, ?)""",
            (idea_id, thesis, source, kw_json, now, now),
        )
        self.conn.commit()
        return self.get_idea(idea_id)

    def get_idea(self, idea_id: str) -> Idea:
        row = self.conn.execute(
            "SELECT * FROM ideas WHERE id = ?", (idea_id,)
        ).fetchone()
        if row is None:
            raise ValueError(f"Idea not found: {idea_id}")
        return _row_to_idea(row)

    def list_ideas(
        self,
        maturity: str | None = None,
        enriched_only: bool = False,
        limit: int | None = None,
    ) -> list[Idea]:
        query = "SELECT * FROM ideas WHERE 1=1"
        params: list[Any] = []

        if maturity:
            query += " AND maturity = ?"
            params.append(maturity)

        if enriched_only:
            query += " AND enriched = 1"

        query += " ORDER BY confidence DESC, updated_at DESC"

        if limit:
            query += " LIMIT ?"
            params.append(limit)

        rows = self.conn.execute(query, params).fetchall()
        return [_row_to_idea(r) for r in rows]

    def list_refinable(self, limit: int = 10) -> list[Idea]:
        """List ideas eligible for refinement: not mature, enriched, ordered by stalest first."""
        rows = self.conn.execute(
            """SELECT * FROM ideas
               WHERE maturity != 'mature' AND enriched = 1
               ORDER BY updated_at ASC
               LIMIT ?""",
            (limit,),
        ).fetchall()
        return [_row_to_idea(r) for r in rows]

    def update_idea(self, idea_id: str, **fields: Any) -> None:
        """Update specific fields on an idea."""
        # Serialize JSON fields
        for key in ("evidence", "keywords", "open_questions"):
            if key in fields and isinstance(fields[key], list):
                fields[key] = json.dumps(fields[key])

        fields["updated_at"] = _now_iso()
        set_clause = ", ".join(f"{k} = ?" for k in fields)
        values = list(fields.values()) + [idea_id]
        self.conn.execute(
            f"UPDATE ideas SET {set_clause} WHERE id = ?", values
        )
        self.conn.commit()

    def delete_idea(self, idea_id: str) -> None:
        """Delete an idea and cascade to logs/annotations."""
        idea = self.get_idea(idea_id)
        if idea.graduated_bead_id and idea.graduated_bead_id != "PENDING":
            raise ValueError(
                f"Cannot delete graduated idea {idea_id} (bead: {idea.graduated_bead_id})"
            )
        self.conn.execute("DELETE FROM ideas WHERE id = ?", (idea_id,))
        self.conn.commit()

    # --- Advisory locking ---

    def try_lock(self, idea_id: str, stale_minutes: int = 10) -> bool:
        """Try to acquire advisory lock. Returns True if acquired."""
        now = _now_iso()
        row = self.conn.execute(
            "SELECT locked_at FROM ideas WHERE id = ?", (idea_id,)
        ).fetchone()
        if row is None:
            return False

        if row["locked_at"]:
            locked = datetime.fromisoformat(row["locked_at"])
            age_min = (datetime.now(timezone.utc) - locked).total_seconds() / 60
            if age_min < stale_minutes:
                return False  # Another process holds the lock

        self.conn.execute(
            "UPDATE ideas SET locked_at = ? WHERE id = ?", (now, idea_id)
        )
        self.conn.commit()
        return True

    def unlock(self, idea_id: str) -> None:
        self.conn.execute(
            "UPDATE ideas SET locked_at = NULL WHERE id = ?", (idea_id,)
        )
        self.conn.commit()

    # --- Refinement logs ---

    def log_refinement(
        self,
        idea_id: str,
        trigger: str,
        summary: str,
        confidence_before: float,
        confidence_after: float,
        new_evidence: list[str] | None = None,
        context_hash: str | None = None,
    ) -> RefinementLog:
        log_id = _ulid()
        now = _now_iso()
        self.conn.execute(
            """INSERT INTO refinement_log
               (id, idea_id, trigger, summary, confidence_before, confidence_after, new_evidence, context_hash, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                log_id,
                idea_id,
                trigger,
                summary,
                confidence_before,
                confidence_after,
                json.dumps(new_evidence or []),
                context_hash,
                now,
            ),
        )
        self.conn.commit()
        return RefinementLog(
            id=log_id,
            idea_id=idea_id,
            trigger=trigger,
            summary=summary,
            confidence_before=confidence_before,
            confidence_after=confidence_after,
            new_evidence=new_evidence or [],
            context_hash=context_hash,
            created_at=datetime.fromisoformat(now),
        )

    def last_context_hash(self, idea_id: str) -> str | None:
        row = self.conn.execute(
            "SELECT context_hash FROM refinement_log WHERE idea_id = ? ORDER BY created_at DESC LIMIT 1",
            (idea_id,),
        ).fetchone()
        return row["context_hash"] if row else None

    def refinement_history(self, idea_id: str, limit: int = 5) -> list[RefinementLog]:
        rows = self.conn.execute(
            "SELECT * FROM refinement_log WHERE idea_id = ? ORDER BY created_at DESC LIMIT ?",
            (idea_id, limit),
        ).fetchall()
        return [_row_to_refinement(r) for r in rows]

    # --- Annotations ---

    def add_annotation(
        self, idea_id: str, source: str, annotation_type: str, body: str
    ) -> Annotation:
        ann_id = _ulid()
        now = _now_iso()
        self.conn.execute(
            """INSERT INTO annotations (id, idea_id, source, annotation_type, body, created_at)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (ann_id, idea_id, source, annotation_type, body, now),
        )
        self.conn.commit()
        return Annotation(
            id=ann_id,
            idea_id=idea_id,
            source=source,
            annotation_type=annotation_type,
            body=body,
            created_at=datetime.fromisoformat(now),
        )

    def annotations_for(self, idea_id: str) -> list[Annotation]:
        rows = self.conn.execute(
            "SELECT * FROM annotations WHERE idea_id = ? ORDER BY created_at ASC",
            (idea_id,),
        ).fetchall()
        return [_row_to_annotation(r) for r in rows]

    def has_graduation_approval(self, idea_id: str) -> bool:
        row = self.conn.execute(
            "SELECT COUNT(*) as cnt FROM annotations WHERE idea_id = ? AND annotation_type = 'graduation_approval'",
            (idea_id,),
        ).fetchone()
        return row["cnt"] > 0

    # --- Stats ---

    def stats(self) -> dict[str, Any]:
        maturity_counts = {}
        for row in self.conn.execute(
            "SELECT maturity, COUNT(*) as cnt FROM ideas GROUP BY maturity"
        ).fetchall():
            maturity_counts[row["maturity"]] = row["cnt"]

        unenriched = self.conn.execute(
            "SELECT COUNT(*) as cnt FROM ideas WHERE enriched = 0"
        ).fetchone()["cnt"]

        last_refine = self.conn.execute(
            "SELECT MAX(created_at) as ts FROM refinement_log"
        ).fetchone()["ts"]

        return {
            "total": sum(maturity_counts.values()),
            "by_maturity": maturity_counts,
            "unenriched": unenriched,
            "last_refinement": last_refine,
        }


def _row_to_idea(row: sqlite3.Row) -> Idea:
    return Idea(
        id=row["id"],
        thesis=row["thesis"],
        evidence=json.loads(row["evidence"]),
        confidence=row["confidence"],
        maturity=row["maturity"],
        keywords=json.loads(row["keywords"]),
        open_questions=json.loads(row["open_questions"]),
        garden_id=row["garden_id"],
        source=row["source"],
        graduated_bead_id=row["graduated_bead_id"],
        enriched=bool(row["enriched"]),
        locked_at=(
            datetime.fromisoformat(row["locked_at"]) if row["locked_at"] else None
        ),
        created_at=datetime.fromisoformat(row["created_at"]),
        updated_at=datetime.fromisoformat(row["updated_at"]),
    )


def _row_to_refinement(row: sqlite3.Row) -> RefinementLog:
    return RefinementLog(
        id=row["id"],
        idea_id=row["idea_id"],
        trigger=row["trigger"],
        summary=row["summary"],
        confidence_before=row["confidence_before"],
        confidence_after=row["confidence_after"],
        new_evidence=json.loads(row["new_evidence"]),
        context_hash=row["context_hash"],
        created_at=datetime.fromisoformat(row["created_at"]),
    )


def _row_to_annotation(row: sqlite3.Row) -> Annotation:
    return Annotation(
        id=row["id"],
        idea_id=row["idea_id"],
        source=row["source"],
        annotation_type=row["annotation_type"],
        body=row["body"],
        created_at=datetime.fromisoformat(row["created_at"]),
    )
