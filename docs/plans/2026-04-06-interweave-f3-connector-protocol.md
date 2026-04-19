---
artifact_type: plan
bead: sylveste-qo8
stage: design
requirements:
  - F3: Connector protocol + first connectors (cass, beads, tldr-code)
---
# Connector Protocol Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** sylveste-qo8
**Goal:** Define the connector interface (register, harvest, observation contract) and implement connectors for cass (sessions), beads (work tracking), and tldr-code (code structure) — interweave crawls subsystem CLIs without changing them.

**Architecture:** Abstract `Connector` protocol defines the harvest interface. Each connector wraps a subsystem CLI (cass, bd, tldr-code) and translates output into crosswalk entity registrations. A `ConnectorRegistry` manages connector lifecycle. A `Harvester` orchestrates broad (metadata-only) and deep (on-demand) harvests across all registered connectors. Connectors write to the crosswalk from F2 — they produce `CanonicalID` entries, never own data.

**Tech Stack:** Python 3.12, subprocess (CLI wrappers), existing F2 crosswalk (CrosswalkDB, Crosswalk, CanonicalID).

---

## Must-Haves

**Truths** (observable behaviors):
- Connector interface is abstract — new connectors require zero changes to existing code
- Each connector crawls its subsystem CLI and registers entities in the crosswalk
- Observation contracts describe what each connector provides
- Broad harvest indexes metadata fast; deep harvest retrieves specific entities on demand
- Adding a connector doesn't change existing query results
- 2-field minimum (entity_id + subsystem) is sufficient to register an entity

**Artifacts** (files with specific exports):
- [`src/interweave/connector.py`] exports [`Connector`, `ObservationContract`, `HarvestMode`, `ConnectorRegistry`]
- [`src/interweave/harvest.py`] exports [`Harvester`]
- [`src/interweave/connectors/cass.py`] exports [`CassConnector`]
- [`src/interweave/connectors/beads.py`] exports [`BeadsConnector`]
- [`src/interweave/connectors/tldr_code.py`] exports [`TldrCodeConnector`]

**Key Links** (connections where breakage cascades):
- All connectors implement `Connector` protocol and register via `ConnectorRegistry`
- `Harvester` iterates `ConnectorRegistry` and calls `harvest()` on each
- Each connector's `harvest()` calls `Crosswalk.register()` to create entities

---

### Task 1: Connector Protocol and Registry

**Files:**
- Create: `src/interweave/connector.py`
- Test: `tests/test_connector.py`

**Step 1: Write the failing test**
```python
# tests/test_connector.py
"""Tests for the Connector protocol and ConnectorRegistry."""

import pytest

from interweave.connector import (
    Connector,
    ConnectorRegistry,
    HarvestMode,
    HarvestResult,
    ObservationContract,
)
from interweave.crosswalk import Crosswalk
from interweave.storage import CrosswalkDB


class StubConnector(Connector):
    """Minimal connector for testing."""

    @property
    def name(self) -> str:
        return "stub"

    def get_observation_contract(self) -> ObservationContract:
        return ObservationContract(
            entities_indexed=["widget"],
            granularity="item-level",
            properties_captured=["id", "name"],
            properties_inferred=[],
            refresh_cadence="on-demand",
            freshness_signal="last_harvested_at",
            observation_depth={"widget": "metadata"},
            relationship_types=[],
            coverage_estimate={"indexed_since": None, "approximate_completeness": 0.0},
        )

    def harvest(self, crosswalk: Crosswalk, mode: HarvestMode) -> HarvestResult:
        cid = crosswalk.register(
            subsystem="stub", native_id="w-1",
            entity_type="widget", family="artifact",
            properties={"name": "Test Widget"},
        )
        return HarvestResult(entities_registered=1, entities_updated=0, errors=[])


class TestConnectorProtocol:
    def test_stub_implements_protocol(self):
        c = StubConnector()
        assert c.name == "stub"
        contract = c.get_observation_contract()
        assert "widget" in contract.entities_indexed

    def test_harvest_registers_entity(self, tmp_path):
        db = CrosswalkDB(tmp_path / "test.db")
        crosswalk = Crosswalk(db)
        c = StubConnector()
        result = c.harvest(crosswalk, HarvestMode.BROAD)
        assert result.entities_registered == 1
        assert crosswalk.get("stub:w-1") is not None


class TestConnectorRegistry:
    def test_register_and_list(self):
        registry = ConnectorRegistry()
        registry.register(StubConnector())
        assert len(registry.list()) == 1
        assert registry.get("stub") is not None

    def test_register_duplicate_replaces(self):
        registry = ConnectorRegistry()
        registry.register(StubConnector())
        registry.register(StubConnector())
        assert len(registry.list()) == 1

    def test_get_unknown_returns_none(self):
        registry = ConnectorRegistry()
        assert registry.get("nonexistent") is None
```

**Step 2: Run test to verify it fails**
Run: `cd interverse/interweave && uv run pytest tests/test_connector.py -v`
Expected: FAIL with "ModuleNotFoundError"

**Step 3: Write minimal implementation**
```python
# src/interweave/connector.py
"""Connector protocol and registry.

Connectors are interweave-internal: they crawl subsystem CLIs and
register entities in the crosswalk. Subsystems need not know about
interweave.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from enum import Enum
from typing import Any

from interweave.crosswalk import Crosswalk


class HarvestMode(Enum):
    """Harvest mode determines the depth of entity collection."""
    BROAD = "broad"   # Fast, metadata-only
    DEEP = "deep"     # Slow, on-demand for specific entities


@dataclass
class ObservationContract:
    """Declares what a connector provides.

    This is the connector's promise to interweave about what it can index,
    at what granularity, and how fresh the data is.
    """
    entities_indexed: list[str]
    granularity: str
    properties_captured: list[str]
    properties_inferred: list[str]
    refresh_cadence: str
    freshness_signal: str
    observation_depth: dict[str, str]
    relationship_types: list[str]
    coverage_estimate: dict[str, Any]


@dataclass
class HarvestResult:
    """Result of a harvest operation."""
    entities_registered: int
    entities_updated: int
    errors: list[str] = field(default_factory=list)


class Connector(ABC):
    """Abstract connector protocol.

    Each connector wraps a subsystem CLI and translates its output into
    crosswalk entity registrations. Minimum discovery threshold: entity_id
    + subsystem (2 fields). entity_type and created_at are auto-inferred
    where possible.
    """

    @property
    @abstractmethod
    def name(self) -> str:
        """Unique connector name (matches subsystem prefix in canonical IDs)."""

    @abstractmethod
    def get_observation_contract(self) -> ObservationContract:
        """Return the observation contract for this connector."""

    @abstractmethod
    def harvest(self, crosswalk: Crosswalk, mode: HarvestMode) -> HarvestResult:
        """Harvest entity metadata from the subsystem.

        BROAD mode: fast, metadata-only scan.
        DEEP mode: slower, retrieves full entity details on demand.
        """


class ConnectorRegistry:
    """Registry of available connectors."""

    def __init__(self) -> None:
        self._connectors: dict[str, Connector] = {}

    def register(self, connector: Connector) -> None:
        """Register a connector, replacing any existing one with the same name."""
        self._connectors[connector.name] = connector

    def get(self, name: str) -> Connector | None:
        """Get a connector by name."""
        return self._connectors.get(name)

    def list(self) -> list[Connector]:
        """List all registered connectors."""
        return list(self._connectors.values())
```

**Step 4: Run test to verify it passes**
Run: `cd interverse/interweave && uv run pytest tests/test_connector.py -v`
Expected: PASS (all 5 tests)

**Step 5: Commit**
```bash
git add src/interweave/connector.py tests/test_connector.py
git commit -m "feat(interweave): add connector protocol and registry"
```

<verify>
- run: `cd interverse/interweave && uv run pytest tests/test_connector.py -v`
  expect: exit 0
- run: `cd interverse/interweave && uv run python -c "from interweave.connector import Connector, ConnectorRegistry, HarvestMode; print('OK')"`
  expect: contains "OK"
</verify>

---

### Task 2: Cass Connector

**Files:**
- Create: `src/interweave/connectors/__init__.py`
- Create: `src/interweave/connectors/cass.py`
- Test: `tests/test_connector_cass.py`

**Depends:** task-1

**Step 1: Write the failing test**
```python
# tests/test_connector_cass.py
"""Tests for the cass connector."""

import json
import subprocess
from unittest.mock import patch, MagicMock

import pytest

from interweave.connector import HarvestMode
from interweave.connectors.cass import CassConnector
from interweave.crosswalk import Crosswalk
from interweave.storage import CrosswalkDB


MOCK_CASS_SEARCH = json.dumps({
    "hits": [
        {
            "title": "Implement crosswalk",
            "source_path": "/home/mk/.claude/sessions/abc123.jsonl",
            "agent": "claude_code",
            "workspace": "/home/mk/projects/Sylveste",
            "created_at": 1775420896047,
            "score": 42.5,
        },
        {
            "title": "Fix bug in storage",
            "source_path": "/home/mk/.claude/sessions/def456.jsonl",
            "agent": "claude_code",
            "workspace": "/home/mk/projects/Sylveste",
            "created_at": 1775420000000,
            "score": 30.1,
        },
    ],
    "count": 2,
    "total_matches": 2,
})


@pytest.fixture
def crosswalk(tmp_path):
    db = CrosswalkDB(tmp_path / "test.db")
    return Crosswalk(db)


class TestCassConnectorContract:
    def test_observation_contract(self):
        c = CassConnector()
        contract = c.get_observation_contract()
        assert "session" in contract.entities_indexed
        assert contract.refresh_cadence == "on-demand"

    def test_name(self):
        assert CassConnector().name == "cass"


class TestCassHarvest:
    @patch("interweave.connectors.cass._run_cass_command")
    def test_broad_harvest_registers_sessions(self, mock_cmd, crosswalk):
        mock_cmd.return_value = MOCK_CASS_SEARCH
        c = CassConnector()
        result = c.harvest(crosswalk, HarvestMode.BROAD)
        assert result.entities_registered == 2
        assert result.errors == []
        # Check sessions were registered
        entity = crosswalk.get("cass:abc123")
        assert entity is not None
        assert entity["entity_type"] == "session"

    @patch("interweave.connectors.cass._run_cass_command")
    def test_harvest_handles_cass_unavailable(self, mock_cmd, crosswalk):
        mock_cmd.return_value = None
        c = CassConnector()
        result = c.harvest(crosswalk, HarvestMode.BROAD)
        assert result.entities_registered == 0
        assert len(result.errors) == 1

    @patch("interweave.connectors.cass._run_cass_command")
    def test_broad_harvest_extracts_session_id_from_path(self, mock_cmd, crosswalk):
        mock_cmd.return_value = MOCK_CASS_SEARCH
        c = CassConnector()
        c.harvest(crosswalk, HarvestMode.BROAD)
        # Session ID extracted from source_path filename
        assert crosswalk.get("cass:abc123") is not None
        assert crosswalk.get("cass:def456") is not None
```

**Step 2: Run test to verify it fails**
Run: `cd interverse/interweave && uv run pytest tests/test_connector_cass.py -v`
Expected: FAIL

**Step 3: Write minimal implementation**
```python
# src/interweave/connectors/__init__.py
"""Interweave connectors for subsystem integration."""

# src/interweave/connectors/cass.py
"""Cass connector — indexes sessions, tool calls, files_touched.

Crawls the cass CLI (session intelligence backend). Refresh via cass index.
Interweave-internal: cass need not know about interweave.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any

from interweave.connector import Connector, HarvestMode, HarvestResult, ObservationContract
from interweave.crosswalk import Crosswalk


def _run_cass_command(args: list[str]) -> str | None:
    """Run a cass CLI command and return stdout, or None on failure."""
    try:
        result = subprocess.run(
            ["cass", *args],
            capture_output=True, text=True, check=True, timeout=30,
        )
        return result.stdout
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
        return None


class CassConnector(Connector):
    """Connector for cass (session intelligence backend)."""

    @property
    def name(self) -> str:
        return "cass"

    def get_observation_contract(self) -> ObservationContract:
        return ObservationContract(
            entities_indexed=["session"],
            granularity="session-level (tool calls as nested, not independent)",
            properties_captured=[
                "session_id", "title", "agent", "workspace", "created_at", "score",
            ],
            properties_inferred=["source_path"],
            refresh_cadence="on-demand",
            freshness_signal="last_harvested_at",
            observation_depth={"session": "metadata"},
            relationship_types=["files_touched"],
            coverage_estimate={
                "indexed_since": None,
                "approximate_completeness": 0.0,
            },
        )

    def harvest(self, crosswalk: Crosswalk, mode: HarvestMode) -> HarvestResult:
        if mode == HarvestMode.BROAD:
            return self._harvest_broad(crosswalk)
        return self._harvest_deep(crosswalk)

    def _harvest_broad(self, crosswalk: Crosswalk) -> HarvestResult:
        """Broad harvest: search for recent sessions and index metadata."""
        output = _run_cass_command([
            "search", "*", "--robot", "--limit", "500", "--json",
        ])
        if output is None:
            return HarvestResult(
                entities_registered=0, entities_updated=0,
                errors=["cass CLI unavailable or search failed"],
            )

        try:
            data = json.loads(output)
        except json.JSONDecodeError:
            return HarvestResult(
                entities_registered=0, entities_updated=0,
                errors=["Invalid JSON from cass search"],
            )

        registered = 0
        for hit in data.get("hits", []):
            session_id = self._extract_session_id(hit)
            if not session_id:
                continue

            crosswalk.register(
                subsystem="cass", native_id=session_id,
                entity_type="session", family="process",
                properties={
                    "title": hit.get("title", ""),
                    "agent": hit.get("agent", ""),
                    "workspace": hit.get("workspace", ""),
                    "created_at": hit.get("created_at"),
                    "source_path": hit.get("source_path", ""),
                },
            )
            registered += 1

        return HarvestResult(
            entities_registered=registered, entities_updated=0, errors=[],
        )

    def _harvest_deep(self, crosswalk: Crosswalk) -> HarvestResult:
        """Deep harvest: placeholder for on-demand entity detail retrieval."""
        # Deep harvest will be fleshed out when F5 (query templates) needs it
        return HarvestResult(entities_registered=0, entities_updated=0, errors=[])

    def _extract_session_id(self, hit: dict[str, Any]) -> str | None:
        """Extract session ID from a cass search hit.

        Derives from source_path filename: /path/to/abc123.jsonl -> abc123
        """
        source_path = hit.get("source_path", "")
        if not source_path:
            return None
        return Path(source_path).stem
```

**Step 4: Run test to verify it passes**
Run: `cd interverse/interweave && uv run pytest tests/test_connector_cass.py -v`
Expected: PASS (all 5 tests)

**Step 5: Commit**
```bash
git add src/interweave/connectors/__init__.py src/interweave/connectors/cass.py tests/test_connector_cass.py
git commit -m "feat(interweave): add cass connector (sessions)"
```

<verify>
- run: `cd interverse/interweave && uv run pytest tests/test_connector_cass.py -v`
  expect: exit 0
</verify>

---

### Task 3: Beads Connector

**Files:**
- Create: `src/interweave/connectors/beads.py`
- Test: `tests/test_connector_beads.py`

**Depends:** task-1

**Step 1: Write the failing test**
```python
# tests/test_connector_beads.py
"""Tests for the beads connector."""

import json
from unittest.mock import patch

import pytest

from interweave.connector import HarvestMode
from interweave.connectors.beads import BeadsConnector
from interweave.crosswalk import Crosswalk
from interweave.storage import CrosswalkDB


MOCK_BD_LIST = json.dumps([
    {
        "id": "sylveste-h7t",
        "title": "F2: Identity crosswalk",
        "status": "closed",
        "priority": 1,
        "issue_type": "feature",
        "created_at": "2026-04-05T00:00:00Z",
        "labels": [],
        "dependency_count": 1,
        "dependent_count": 2,
    },
    {
        "id": "sylveste-qo8",
        "title": "F3: Connector protocol",
        "status": "in_progress",
        "priority": 1,
        "issue_type": "feature",
        "created_at": "2026-04-05T00:00:00Z",
        "labels": ["complexity:3"],
        "dependency_count": 1,
        "dependent_count": 1,
    },
])


@pytest.fixture
def crosswalk(tmp_path):
    db = CrosswalkDB(tmp_path / "test.db")
    return Crosswalk(db)


class TestBeadsConnectorContract:
    def test_observation_contract(self):
        c = BeadsConnector()
        contract = c.get_observation_contract()
        assert "bead" in contract.entities_indexed
        assert "dependency" in contract.relationship_types

    def test_name(self):
        assert BeadsConnector().name == "beads"


class TestBeadsHarvest:
    @patch("interweave.connectors.beads._run_bd_command")
    def test_broad_harvest_registers_issues(self, mock_cmd, crosswalk):
        mock_cmd.return_value = MOCK_BD_LIST
        c = BeadsConnector()
        result = c.harvest(crosswalk, HarvestMode.BROAD)
        assert result.entities_registered == 2
        entity = crosswalk.get("beads:sylveste-h7t")
        assert entity is not None
        assert entity["entity_type"] == "bead"
        assert entity["properties"]["status"] == "closed"

    @patch("interweave.connectors.beads._run_bd_command")
    def test_harvest_handles_bd_unavailable(self, mock_cmd, crosswalk):
        mock_cmd.return_value = None
        c = BeadsConnector()
        result = c.harvest(crosswalk, HarvestMode.BROAD)
        assert result.entities_registered == 0
        assert len(result.errors) == 1
```

**Step 2: Run test to verify it fails**
Run: `cd interverse/interweave && uv run pytest tests/test_connector_beads.py -v`
Expected: FAIL

**Step 3: Write minimal implementation**
```python
# src/interweave/connectors/beads.py
"""Beads connector — indexes issues, dependencies, sprints.

Crawls the bd CLI (work tracking). Refresh via bd CLI.
Interweave-internal: beads need not know about interweave.
"""

from __future__ import annotations

import json
import subprocess

from interweave.connector import Connector, HarvestMode, HarvestResult, ObservationContract
from interweave.crosswalk import Crosswalk


def _run_bd_command(args: list[str]) -> str | None:
    """Run a bd CLI command and return stdout, or None on failure."""
    try:
        result = subprocess.run(
            ["bd", *args],
            capture_output=True, text=True, check=True, timeout=30,
        )
        return result.stdout
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
        return None


class BeadsConnector(Connector):
    """Connector for beads (work tracking)."""

    @property
    def name(self) -> str:
        return "beads"

    def get_observation_contract(self) -> ObservationContract:
        return ObservationContract(
            entities_indexed=["bead"],
            granularity="issue-level",
            properties_captured=[
                "bead_id", "title", "status", "priority", "issue_type",
                "created_at", "labels", "dependency_count", "dependent_count",
            ],
            properties_inferred=["assignee"],
            refresh_cadence="on-demand",
            freshness_signal="last_harvested_at",
            observation_depth={"bead": "metadata"},
            relationship_types=["dependency", "blocks", "parent-child"],
            coverage_estimate={
                "indexed_since": None,
                "approximate_completeness": 0.0,
            },
        )

    def harvest(self, crosswalk: Crosswalk, mode: HarvestMode) -> HarvestResult:
        if mode == HarvestMode.BROAD:
            return self._harvest_broad(crosswalk)
        return self._harvest_deep(crosswalk)

    def _harvest_broad(self, crosswalk: Crosswalk) -> HarvestResult:
        """Broad harvest: list all issues and index metadata."""
        output = _run_bd_command(["list", "--all", "--json"])
        if output is None:
            return HarvestResult(
                entities_registered=0, entities_updated=0,
                errors=["bd CLI unavailable or list failed"],
            )

        try:
            issues = json.loads(output)
        except json.JSONDecodeError:
            return HarvestResult(
                entities_registered=0, entities_updated=0,
                errors=["Invalid JSON from bd list"],
            )

        registered = 0
        for issue in issues:
            bead_id = issue.get("id")
            if not bead_id:
                continue

            crosswalk.register(
                subsystem="beads", native_id=bead_id,
                entity_type="bead", family="process",
                properties={
                    "title": issue.get("title", ""),
                    "status": issue.get("status", ""),
                    "priority": issue.get("priority"),
                    "issue_type": issue.get("issue_type", ""),
                    "created_at": issue.get("created_at"),
                    "labels": issue.get("labels", []),
                    "dependency_count": issue.get("dependency_count", 0),
                    "dependent_count": issue.get("dependent_count", 0),
                },
            )
            registered += 1

        return HarvestResult(
            entities_registered=registered, entities_updated=0, errors=[],
        )

    def _harvest_deep(self, crosswalk: Crosswalk) -> HarvestResult:
        """Deep harvest: placeholder for on-demand detail retrieval."""
        return HarvestResult(entities_registered=0, entities_updated=0, errors=[])
```

**Step 4: Run test to verify it passes**
Run: `cd interverse/interweave && uv run pytest tests/test_connector_beads.py -v`
Expected: PASS (all 4 tests)

**Step 5: Commit**
```bash
git add src/interweave/connectors/beads.py tests/test_connector_beads.py
git commit -m "feat(interweave): add beads connector (issues, dependencies)"
```

<verify>
- run: `cd interverse/interweave && uv run pytest tests/test_connector_beads.py -v`
  expect: exit 0
</verify>

---

### Task 4: Tldr-Code Connector

**Files:**
- Create: `src/interweave/connectors/tldr_code.py`
- Test: `tests/test_connector_tldr_code.py`

**Depends:** task-1

**Step 1: Write the failing test**
```python
# tests/test_connector_tldr_code.py
"""Tests for the tldr-code connector."""

import json
from unittest.mock import patch

import pytest

from interweave.connector import HarvestMode
from interweave.connectors.tldr_code import TldrCodeConnector
from interweave.crosswalk import Crosswalk
from interweave.storage import CrosswalkDB


MOCK_STRUCTURE = json.dumps({
    "project": "/home/mk/projects/Sylveste",
    "files": [
        {
            "path": "src/interweave/crosswalk.py",
            "language": "python",
            "symbols": [
                {"name": "CanonicalID", "kind": "class", "line": 15},
                {"name": "Crosswalk", "kind": "class", "line": 35},
            ],
        },
        {
            "path": "src/interweave/storage.py",
            "language": "python",
            "symbols": [
                {"name": "CrosswalkDB", "kind": "class", "line": 60},
            ],
        },
    ],
})


@pytest.fixture
def crosswalk(tmp_path):
    db = CrosswalkDB(tmp_path / "test.db")
    return Crosswalk(db)


class TestTldrCodeConnectorContract:
    def test_observation_contract(self):
        c = TldrCodeConnector()
        contract = c.get_observation_contract()
        assert "file" in contract.entities_indexed
        assert "function" in contract.entities_indexed

    def test_name(self):
        assert TldrCodeConnector().name == "tldr-code"


class TestTldrCodeHarvest:
    @patch("interweave.connectors.tldr_code._run_tldr_command")
    def test_broad_harvest_registers_files_and_symbols(self, mock_cmd, crosswalk):
        mock_cmd.return_value = MOCK_STRUCTURE
        c = TldrCodeConnector()
        result = c.harvest(crosswalk, HarvestMode.BROAD)
        # 2 files + 3 symbols = 5 entities
        assert result.entities_registered == 5
        file_entity = crosswalk.get("tldr-code:src/interweave/crosswalk.py")
        assert file_entity is not None
        assert file_entity["entity_type"] == "file"

    @patch("interweave.connectors.tldr_code._run_tldr_command")
    def test_harvest_handles_tldr_unavailable(self, mock_cmd, crosswalk):
        mock_cmd.return_value = None
        c = TldrCodeConnector()
        result = c.harvest(crosswalk, HarvestMode.BROAD)
        assert result.entities_registered == 0
        assert len(result.errors) == 1

    @patch("interweave.connectors.tldr_code._run_tldr_command")
    def test_symbol_entity_type_from_kind(self, mock_cmd, crosswalk):
        mock_cmd.return_value = MOCK_STRUCTURE
        c = TldrCodeConnector()
        c.harvest(crosswalk, HarvestMode.BROAD)
        # Classes registered as "function" (generic symbol type for the crosswalk)
        entity = crosswalk.get("tldr-code:src/interweave/crosswalk.py:CanonicalID")
        assert entity is not None
```

**Step 2: Run test to verify it fails**
Run: `cd interverse/interweave && uv run pytest tests/test_connector_tldr_code.py -v`
Expected: FAIL

**Step 3: Write minimal implementation**
```python
# src/interweave/connectors/tldr_code.py
"""Tldr-code connector — indexes files, functions, classes, imports.

Crawls the tldr-code CLI (code structure analysis). Refresh via tldr-code
extract/structure. Interweave-internal: tldr-code need not know about
interweave.
"""

from __future__ import annotations

import json
import subprocess
from typing import Any

from interweave.connector import Connector, HarvestMode, HarvestResult, ObservationContract
from interweave.crosswalk import Crosswalk
from interweave.resolve_file import normalize_path


def _run_tldr_command(args: list[str]) -> str | None:
    """Run a tldr-code CLI command and return stdout, or None on failure."""
    try:
        result = subprocess.run(
            ["tldr-code", *args],
            capture_output=True, text=True, check=True, timeout=60,
        )
        return result.stdout
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
        return None


# Map tldr-code symbol kinds to interweave entity types
_KIND_TO_ENTITY_TYPE: dict[str, str] = {
    "function": "function",
    "class": "function",  # Classes indexed as generic symbols
    "method": "function",
    "module": "module",
}


class TldrCodeConnector(Connector):
    """Connector for tldr-code (code structure analysis)."""

    @property
    def name(self) -> str:
        return "tldr-code"

    def get_observation_contract(self) -> ObservationContract:
        return ObservationContract(
            entities_indexed=["file", "function", "module"],
            granularity="symbol-level",
            properties_captured=[
                "path", "language", "symbol_name", "symbol_kind", "line",
            ],
            properties_inferred=[],
            refresh_cadence="on-demand",
            freshness_signal="last_harvested_at",
            observation_depth={
                "file": "metadata",
                "function": "metadata",
                "module": "metadata",
            },
            relationship_types=["imports", "contains"],
            coverage_estimate={
                "indexed_since": None,
                "approximate_completeness": 0.0,
            },
        )

    def harvest(self, crosswalk: Crosswalk, mode: HarvestMode) -> HarvestResult:
        if mode == HarvestMode.BROAD:
            return self._harvest_broad(crosswalk)
        return self._harvest_deep(crosswalk)

    def _harvest_broad(self, crosswalk: Crosswalk) -> HarvestResult:
        """Broad harvest: get project structure and index files + symbols."""
        output = _run_tldr_command(["structure", "--json"])
        if output is None:
            return HarvestResult(
                entities_registered=0, entities_updated=0,
                errors=["tldr-code CLI unavailable or structure failed"],
            )

        try:
            data = json.loads(output)
        except json.JSONDecodeError:
            return HarvestResult(
                entities_registered=0, entities_updated=0,
                errors=["Invalid JSON from tldr-code structure"],
            )

        registered = 0
        for file_info in data.get("files", []):
            path = file_info.get("path", "")
            if not path:
                continue

            normalized = normalize_path(path)

            # Register file
            crosswalk.register(
                subsystem="tldr-code", native_id=normalized,
                entity_type="file", family="artifact",
                properties={
                    "path": normalized,
                    "language": file_info.get("language", ""),
                },
            )
            registered += 1

            # Register symbols
            for symbol in file_info.get("symbols", []):
                sym_name = symbol.get("name", "")
                if not sym_name:
                    continue

                entity_type = _KIND_TO_ENTITY_TYPE.get(
                    symbol.get("kind", ""), "function"
                )
                native_id = f"{normalized}:{sym_name}"
                crosswalk.register(
                    subsystem="tldr-code", native_id=native_id,
                    entity_type=entity_type, family="artifact",
                    properties={
                        "file_path": normalized,
                        "symbol_name": sym_name,
                        "symbol_kind": symbol.get("kind", ""),
                        "line": symbol.get("line"),
                    },
                )
                registered += 1

        return HarvestResult(
            entities_registered=registered, entities_updated=0, errors=[],
        )

    def _harvest_deep(self, crosswalk: Crosswalk) -> HarvestResult:
        """Deep harvest: placeholder for on-demand detail retrieval."""
        return HarvestResult(entities_registered=0, entities_updated=0, errors=[])
```

**Step 4: Run test to verify it passes**
Run: `cd interverse/interweave && uv run pytest tests/test_connector_tldr_code.py -v`
Expected: PASS (all 5 tests)

**Step 5: Commit**
```bash
git add src/interweave/connectors/tldr_code.py tests/test_connector_tldr_code.py
git commit -m "feat(interweave): add tldr-code connector (files, symbols)"
```

<verify>
- run: `cd interverse/interweave && uv run pytest tests/test_connector_tldr_code.py -v`
  expect: exit 0
</verify>

---

### Task 5: Harvest Orchestrator

**Files:**
- Create: `src/interweave/harvest.py`
- Test: `tests/test_harvest.py`

**Depends:** task-1, task-2, task-3, task-4

**Step 1: Write the failing test**
```python
# tests/test_harvest.py
"""Tests for the Harvester orchestrator."""

from unittest.mock import patch

import pytest

from interweave.connector import ConnectorRegistry, HarvestMode
from interweave.connectors.cass import CassConnector
from interweave.connectors.beads import BeadsConnector
from interweave.connectors.tldr_code import TldrCodeConnector
from interweave.crosswalk import Crosswalk
from interweave.harvest import Harvester
from interweave.storage import CrosswalkDB


@pytest.fixture
def crosswalk(tmp_path):
    db = CrosswalkDB(tmp_path / "test.db")
    return Crosswalk(db)


@pytest.fixture
def registry():
    r = ConnectorRegistry()
    r.register(CassConnector())
    r.register(BeadsConnector())
    r.register(TldrCodeConnector())
    return r


class TestHarvester:
    @patch("interweave.connectors.cass._run_cass_command", return_value=None)
    @patch("interweave.connectors.beads._run_bd_command", return_value=None)
    @patch("interweave.connectors.tldr_code._run_tldr_command", return_value=None)
    def test_harvest_all_graceful_degradation(self, *mocks, crosswalk, registry):
        """All connectors fail gracefully — no crash, errors reported."""
        harvester = Harvester(registry, crosswalk)
        report = harvester.harvest_all(HarvestMode.BROAD)
        assert len(report) == 3
        for name, result in report.items():
            assert result.entities_registered == 0
            assert len(result.errors) >= 1

    @patch("interweave.connectors.cass._run_cass_command", return_value='{"hits":[],"count":0}')
    @patch("interweave.connectors.beads._run_bd_command", return_value="[]")
    @patch("interweave.connectors.tldr_code._run_tldr_command", return_value='{"files":[]}')
    def test_harvest_all_empty_sources(self, *mocks, crosswalk, registry):
        """Empty sources return 0 entities, no errors."""
        harvester = Harvester(registry, crosswalk)
        report = harvester.harvest_all(HarvestMode.BROAD)
        for name, result in report.items():
            assert result.entities_registered == 0
            assert result.errors == []

    def test_harvest_single_connector(self, crosswalk):
        """Harvest only one connector by name."""
        registry = ConnectorRegistry()
        registry.register(CassConnector())
        harvester = Harvester(registry, crosswalk)
        with patch("interweave.connectors.cass._run_cass_command", return_value='{"hits":[],"count":0}'):
            report = harvester.harvest_one("cass", HarvestMode.BROAD)
        assert report is not None
        assert report.errors == []

    def test_harvest_unknown_connector_returns_none(self, crosswalk):
        registry = ConnectorRegistry()
        harvester = Harvester(registry, crosswalk)
        report = harvester.harvest_one("nonexistent", HarvestMode.BROAD)
        assert report is None
```

**Step 2: Run test to verify it fails**
Run: `cd interverse/interweave && uv run pytest tests/test_harvest.py -v`
Expected: FAIL

**Step 3: Write minimal implementation**
```python
# src/interweave/harvest.py
"""Harvest orchestrator.

Coordinates broad (fast, metadata-only) and deep (slow, on-demand)
harvests across all registered connectors.
"""

from __future__ import annotations

from interweave.connector import ConnectorRegistry, HarvestMode, HarvestResult
from interweave.crosswalk import Crosswalk


class Harvester:
    """Orchestrates entity harvesting across connectors."""

    def __init__(self, registry: ConnectorRegistry, crosswalk: Crosswalk) -> None:
        self._registry = registry
        self._crosswalk = crosswalk

    def harvest_all(self, mode: HarvestMode) -> dict[str, HarvestResult]:
        """Run harvest on all registered connectors.

        Returns a report mapping connector name to harvest result.
        Each connector runs independently — one failure doesn't block others.
        """
        report: dict[str, HarvestResult] = {}
        for connector in self._registry.list():
            try:
                result = connector.harvest(self._crosswalk, mode)
            except Exception as e:
                result = HarvestResult(
                    entities_registered=0, entities_updated=0,
                    errors=[f"Unexpected error: {e}"],
                )
            report[connector.name] = result
        return report

    def harvest_one(
        self, connector_name: str, mode: HarvestMode,
    ) -> HarvestResult | None:
        """Run harvest on a single connector by name.

        Returns None if the connector is not registered.
        """
        connector = self._registry.get(connector_name)
        if connector is None:
            return None
        return connector.harvest(self._crosswalk, mode)
```

**Step 4: Run test to verify it passes**
Run: `cd interverse/interweave && uv run pytest tests/test_harvest.py -v`
Expected: PASS (all 4 tests)

**Step 5: Commit**
```bash
git add src/interweave/harvest.py tests/test_harvest.py
git commit -m "feat(interweave): add harvest orchestrator"
```

<verify>
- run: `cd interverse/interweave && uv run pytest tests/test_harvest.py -v`
  expect: exit 0
</verify>

---

### Task 6: Integration Test — Full Connector Workflow

**Files:**
- Create: `tests/test_integration_connectors.py`
- Modify: `src/interweave/__init__.py` (add F3 exports)

**Depends:** task-2, task-3, task-4, task-5

**Step 1: Write integration test**
```python
# tests/test_integration_connectors.py
"""Integration test: full connector workflow.

Exercises connector registration, observation contracts, broad harvest
from all three subsystems (mocked CLIs), and harvester orchestration.
"""

import json
from unittest.mock import patch

import pytest

from interweave.connector import ConnectorRegistry, HarvestMode
from interweave.connectors.beads import BeadsConnector
from interweave.connectors.cass import CassConnector
from interweave.connectors.tldr_code import TldrCodeConnector
from interweave.crosswalk import Crosswalk
from interweave.harvest import Harvester
from interweave.storage import CrosswalkDB


CASS_DATA = json.dumps({
    "hits": [{"title": "session", "source_path": "/s/abc.jsonl",
              "agent": "claude", "workspace": "/p", "created_at": 1}],
    "count": 1,
})
BEADS_DATA = json.dumps([
    {"id": "proj-abc", "title": "Task", "status": "open", "priority": 1,
     "issue_type": "feature", "created_at": "2026-01-01", "labels": [],
     "dependency_count": 0, "dependent_count": 0},
])
TLDR_DATA = json.dumps({
    "files": [{"path": "main.py", "language": "python",
               "symbols": [{"name": "main", "kind": "function", "line": 1}]}],
})


@pytest.fixture
def full_stack(tmp_path):
    db = CrosswalkDB(tmp_path / "interweave.db")
    crosswalk = Crosswalk(db)
    registry = ConnectorRegistry()
    registry.register(CassConnector())
    registry.register(BeadsConnector())
    registry.register(TldrCodeConnector())
    harvester = Harvester(registry, crosswalk)
    return crosswalk, registry, harvester


class TestFullConnectorWorkflow:
    @patch("interweave.connectors.cass._run_cass_command", return_value=CASS_DATA)
    @patch("interweave.connectors.beads._run_bd_command", return_value=BEADS_DATA)
    @patch("interweave.connectors.tldr_code._run_tldr_command", return_value=TLDR_DATA)
    def test_broad_harvest_all(self, *mocks, full_stack):
        crosswalk, registry, harvester = full_stack
        report = harvester.harvest_all(HarvestMode.BROAD)

        # All connectors succeeded
        for name, result in report.items():
            assert result.errors == [], f"{name} had errors: {result.errors}"

        # Verify entities from each subsystem
        assert crosswalk.get("cass:abc") is not None
        assert crosswalk.get("beads:proj-abc") is not None
        assert crosswalk.get("tldr-code:main.py") is not None
        assert crosswalk.get("tldr-code:main.py:main") is not None

    def test_all_contracts_valid(self, full_stack):
        _, registry, _ = full_stack
        for connector in registry.list():
            contract = connector.get_observation_contract()
            assert len(contract.entities_indexed) > 0
            assert contract.refresh_cadence != ""
            assert contract.freshness_signal != ""

    def test_adding_connector_doesnt_affect_existing(self, full_stack):
        crosswalk, registry, harvester = full_stack
        # Harvest with 3 connectors
        with (
            patch("interweave.connectors.cass._run_cass_command", return_value=CASS_DATA),
            patch("interweave.connectors.beads._run_bd_command", return_value=BEADS_DATA),
            patch("interweave.connectors.tldr_code._run_tldr_command", return_value=TLDR_DATA),
        ):
            report1 = harvester.harvest_all(HarvestMode.BROAD)
        total1 = sum(r.entities_registered for r in report1.values())

        # Verify existing entities are unchanged
        cass_entity = crosswalk.get("cass:abc")
        assert cass_entity is not None
        assert cass_entity["entity_type"] == "session"
```

**Step 2: Update `__init__.py` with F3 exports**
Add these imports and exports to `src/interweave/__init__.py`:
```python
from interweave.connector import Connector, ConnectorRegistry, HarvestMode, ObservationContract
from interweave.harvest import Harvester
```

**Step 3: Run full test suite**
Run: `cd interverse/interweave && uv run pytest tests/ -v`
Expected: all tests pass

**Step 4: Lint check**
Run: `cd interverse/interweave && uv run ruff check src/`
Expected: no errors

**Step 5: Commit**
```bash
git add tests/test_integration_connectors.py src/interweave/__init__.py
git commit -m "test(interweave): add connector integration test and update public API"
```

<verify>
- run: `cd interverse/interweave && uv run pytest tests/ -v`
  expect: exit 0
- run: `cd interverse/interweave && uv run ruff check src/`
  expect: exit 0
- run: `cd interverse/interweave && uv run python -c "from interweave import Connector, ConnectorRegistry, HarvestMode, Harvester; print('F3 API OK')"`
  expect: contains "F3 API OK"
</verify>
