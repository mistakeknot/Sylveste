"""Figure tests for docs/wiki: every checked fact is compared with its source file."""
import json
import re
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent
WIKI = ROOT / "docs" / "wiki" / "src"
ARCH = (ROOT / "agents" / "architecture.md").read_text()
PLUGINS = json.loads((ROOT / "ARCHITECTURE.json").read_text())


def page(rel):
    return (WIKI / rel).read_text()


def layout_rows(text):
    """(path, pillar, notes) for each module row of a markdown table."""
    return re.findall(r"^\| `([^`]+)` \| ([^|]*?) \| (.*) \|$", text, flags=re.M)


def layout_paths():
    return [r[0] for r in layout_rows(ARCH)]


def test_pillar_names_match_glossary():
    glossary = re.search(r"\*\*Pillar\*\* \| One of the (\d+) top-level components of Sylveste: ([^.]+)\.", ARCH)
    count, names = int(glossary.group(1)), [n.strip() for n in glossary.group(2).split(",")]
    assert len(names) == count
    text = page("architecture/pillars.md")
    assert f"Sylveste has {count} pillars" in text
    # Layers: the glossary defines L1/L2/L3 by pillar; Skaffen is "L2" in its own entry.
    layers = {"Intercore": "L1", "Clavain": "L2", "Skaffen": "L2", "Interverse": "L2", "Autarch": "L3", "Interspect": "cross-cutting"}
    assert set(layers) == set(names)
    assert "L1 (Kernel/Intercore)" in ARCH and "L2 (OS/Clavain + Drivers/Interverse)" in ARCH and "L3 (Apps/Autarch)" in ARCH
    assert re.search(r"Skaffen\*\* \| .*L2", ARCH) and "Cross-cutting (not a layer)" in ARCH
    for name in names:
        assert re.search(rf"^\| {name} \| {re.escape(layers[name])} \|", text, flags=re.M), f"pillars.md has the wrong layer for {name}"


def test_layout_table_matches_architecture_doc():
    paths = layout_paths()
    assert paths, "no module paths found in agents/architecture.md"
    text = page("architecture/layout.md")
    assert f"lists {len(paths)} module paths" in text
    want = [r for r in layout_rows(ARCH) if r[0] != "interverse/"]
    got = [r for r in layout_rows(text) if r[0] != "interverse/"]
    assert got == want  # path, pillar and notes must all match
    assert [r[0] for r in layout_rows(text)] == paths
    assert dict((r[0], r[1]) for r in layout_rows(text))["interverse/"] == "Interverse"


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


BAD = [r"/home/", r"/Users/", r"\bq\d{3,4}\b", r"\.ts\.net", r"localhost", r"\b" + "zk" + r"lw\b", r"\.internal\b",
       r"\bclavain\.local\b", r"\bjawn" + r"verse\b", r"\bms" + r"q-\d+", r"\bauth\.[a-z]+\.com"]
ALLOWED_HOSTS = {"github.com", "rust-lang.github.io"}


def hygiene_violations(text):
    found = [f"matches {pat}" for pat in BAD if re.search(pat, text, flags=re.I)]
    for url in re.findall(r"(?:[a-z][a-z0-9+.-]*:)?//[^\s)>\]]+", text, flags=re.I):
        if urlparse(url if not url.startswith("//") else "https:" + url).hostname not in ALLOWED_HOSTS:
            found.append(f"links {url}")
    return found


def test_wiki_pages_follow_public_repo_hygiene():
    for p in WIKI.rglob("*.md"):
        assert not hygiene_violations(p.read_text()), f"{p.relative_to(WIKI)}: {hygiene_violations(p.read_text())}"


def test_hygiene_check_catches_bad_content():
    # Exercise the production scanner: a vacuous pattern list or URL check must fail here.
    host = "zk" + "lw"
    ruling = "ru" + "ling q" + "123"
    samples = ("see /home/x", ruling, "host " + host, "https://github.com.internal.example/x",
               "HTTPS://private.example/x", "[p](//private.example/x)", "ftp://private.example/x")
    for sample in samples:
        assert hygiene_violations(sample), sample
    assert not hygiene_violations("[ok](https://github.com/mistakeknot/Sylveste) and https://rust-lang.github.io/mdBook/")
