"""Figure tests for docs/wiki: every checked fact is compared with its source file."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WIKI = ROOT / "docs" / "wiki" / "src"
ARCH = (ROOT / "agents" / "architecture.md").read_text()
PLUGINS = json.loads((ROOT / "ARCHITECTURE.json").read_text())


def page(rel):
    return (WIKI / rel).read_text()


def layout_paths():
    return re.findall(r"^\| `([^`]+)` \|", ARCH, flags=re.M)


def test_pillar_names_match_glossary():
    glossary = re.search(r"\*\*Pillar\*\* \| One of the (\d+) top-level components of Sylveste: ([^.]+)\.", ARCH)
    count, names = int(glossary.group(1)), [n.strip() for n in glossary.group(2).split(",")]
    assert len(names) == count
    text = page("architecture/pillars.md")
    assert f"Sylveste has {count} pillars" in text
    for name in names:
        assert re.search(rf"^\| {name} \|", text, flags=re.M), f"pillars.md is missing pillar {name}"


def test_layout_table_matches_architecture_doc():
    paths = layout_paths()
    assert paths, "no module paths found in agents/architecture.md"
    text = page("architecture/layout.md")
    assert f"lists {len(paths)} module paths" in text
    assert re.findall(r"^\| `([^`]+)` \|", text, flags=re.M) == paths


def test_dependency_chains_match_architecture_doc():
    chain = ARCH.split("## Key Dependency Chains")[1].split("```")[1].strip("\n")
    lines = [l for l in chain.splitlines() if l.strip()]
    text = page("architecture/dependency-chains.md")
    assert f"records {len(lines)} key dependency chains" in text
    assert chain in text


def test_plugin_count_and_table_match_architecture_json():
    plugins = PLUGINS["plugins"]
    assert PLUGINS["plugin_count"] == len(plugins)
    for rel in ("plugins/README.md", "plugins/map.md"):
        assert f"{len(plugins)} " in page(rel)
    rows = re.findall(r"^\| ([^ |]+) \| ([^ |]+) \| (\d+) \| (\d+) \| (\d+) \| (\d+) \|$", page("plugins/map.md"), flags=re.M)
    got = {r[0]: r[1:] for r in rows if r[0] != "Plugin"}
    want = {
        k: (v["version"], str(len(v["skills"])), str(len(v["commands"])), str(len(v["agents"])), str(len(v["mcp_servers"])))
        for k, v in plugins.items()
    }
    assert got == want


def test_summary_lists_every_page_and_all_exist():
    summary = (WIKI / "SUMMARY.md").read_text()
    linked = set(re.findall(r"\]\(([^)]+\.md)\)", summary))
    for rel in linked:
        assert (WIKI / rel).is_file(), f"SUMMARY.md links missing page {rel}"
    on_disk = {str(p.relative_to(WIKI)) for p in WIKI.rglob("*.md")} - {"SUMMARY.md"}
    assert on_disk == linked


def test_wiki_pages_follow_public_repo_hygiene():
    bad = [r"/home/", r"/Users/", r"\bq\d{3,4}\b", r"\.ts\.net", r"localhost", r"https?://(?!github\.com|rust-lang\.github\.io)"]
    for p in WIKI.rglob("*.md"):
        for pat in bad:
            assert not re.search(pat, p.read_text()), f"{p.relative_to(WIKI)} matches {pat}"
