"""Every tracked *.json file must parse as JSON.

The F1 AGE spike result files once held the benchmark's stderr banner on their
first line (captured with 2>&1), so json.load failed on them.
"""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def test_tracked_json_files_parse():
    names = subprocess.check_output(
        ["git", "ls-files", "-z", "--", "*.json"], cwd=ROOT, text=True
    ).split("\0")
    bad = []
    for name in filter(None, names):
        path = ROOT / name
        if not path.is_file():
            continue
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except (ValueError, UnicodeDecodeError) as exc:
            bad.append(f"{name}: {exc}")
    assert not bad, "tracked JSON files that do not parse:\n" + "\n".join(bad)
