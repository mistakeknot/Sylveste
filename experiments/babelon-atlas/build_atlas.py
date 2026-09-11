#!/usr/bin/env python3
"""Join jawnomicon's symbol tier with bridger's domain registry into one atlas.

Neither repo is modified. This reads jawnomicon's published export and bridger's
derived data files and writes a single `symbol-atlas.json` that a room author
(or an agent building on Babelon) can read without either repo, either graph
database, or the tailnet.

Two tiers, because the two corpora do not have the same provenance:

  structure  jawnomicon's own paraphrase glosses, bridger's taxonomy labels and
             sense *counts*, motif labels, creature names. Nothing here is text
             extracted from a third-party reference work.
  full       adds bridger's `senses[]` and `furniture[]` (phrases extracted from
             Cooper, de Vries and ARAS) and jawnomicon's `short_description`.

jawnomicon's copyright contract (docs/symbol-tier-design-question.md, constraint
6) is "extracted source text never ships; glosses are original paraphrase."
`structure` honours that unchanged; `full` does not, and is for private
consumers only. The builder reports what each tier would ship so the call can be
made on counts rather than vibes.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import re
import subprocess
import sys

# The owner-ratified 9-axis kernel (symbol-tier-design-question.md, constraint 2).
KERNEL = [
    "Volition", "Ethical Framework", "Loyalty", "Power Dynamics",
    "Social Orientation", "Risk Attitude", "Influence Style",
    "Structure Preference", "Manifestation",
]


def norm(value: str) -> str:
    """Match key: case, punctuation and spacing are not identity."""
    return re.sub(r"[^a-z0-9]", "", (value or "").lower())


def title_keys(title: str) -> list[str]:
    """`Ape/Monkey` and `Lake /Pond` are one domain under either half."""
    parts = [norm(p) for p in re.split(r"[/,]", title or "")]
    return [p for p in [norm(title)] + parts if p]


def git_commit(repo: pathlib.Path) -> str | None:
    try:
        out = subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True, timeout=30,
        )
        return out.stdout.strip() or None
    except (OSError, subprocess.SubprocessError):
        return None


def load_jawnomicon(export: pathlib.Path) -> dict:
    bestiary = json.loads(export.read_text(encoding="utf-8"))
    creatures = {c["id"]: c for c in bestiary["creatures"]}
    return {
        "manifest": bestiary["manifest"],
        "symbols": bestiary["vocab"]["symbols"],
        "symbol_index": bestiary["symbol_index"],
        "creatures": creatures,
    }


def creature_card(creature: dict, tier: str) -> dict:
    """What a room author needs about an inhabitant, and nothing else."""
    motifs = [
        r["target"] for r in creature.get("relations", [])
        if r.get("type") == "HAS_MOTIF"
    ]
    powers = [
        r["target"] for r in creature.get("relations", [])
        if r.get("type") == "HAS_POWER"
    ]
    dims = (creature.get("eidogen") or {}).get("dimensions") or {}
    card = {
        "id": creature["id"],
        "name": creature["name"],
        "motifs": motifs,
        "powers": powers,
        "eidogen_kernel": {
            axis: dims[axis] for axis in KERNEL
            if isinstance(dims.get(axis), (int, float))
        },
    }
    if tier == "full":
        card["short_description"] = creature.get("short_description")
    return card


def build(jaw_root: pathlib.Path, bri_root: pathlib.Path, export: pathlib.Path,
          tier: str) -> dict:
    jaw = load_jawnomicon(export)
    domains = json.loads((bri_root / "data" / "domains.json").read_text(encoding="utf-8"))

    by_key: dict[str, dict] = {}
    for domain in domains:
        for key in title_keys(domain["title"]):
            by_key.setdefault(key, domain)

    linked_creature_ids: set[str] = set()
    symbols = []
    matched_domains: set[str] = set()

    for symbol in jaw["symbols"]:
        keys = [norm(symbol["name"]), norm(symbol["slug"].replace("-", " "))]
        domain = next((by_key[k] for k in keys if k in by_key), None)

        entry = {
            "slug": symbol["slug"],
            "name": symbol["name"],
            "register": symbol["register"],
            "gloss": symbol["definition"],
            "attestations": symbol["sources"],
            "in": ["jawnomicon"],
        }

        if domain:
            matched_domains.add(domain["id"])
            entry["in"].append("bridger")
            entry["domain"] = {
                "id": domain["id"],
                "title": domain["title"],
                "world": domain["world"],
                "sub": domain["sub"],
                "sense_count": len(domain.get("senses") or []),
                "furniture_count": len(domain.get("furniture") or []),
                "sources": domain.get("sources") or [],
            }
            if tier == "full":
                entry["domain"]["senses"] = domain.get("senses") or []
                entry["domain"]["furniture"] = domain.get("furniture") or []

        links = jaw["symbol_index"].get(symbol["slug"]) or []
        if links:
            entry["creatures"] = [
                {
                    "id": link["creature_id"],
                    "status": link.get("status"),
                    "evidence": link.get("evidence"),
                }
                for link in links
            ]
            linked_creature_ids.update(link["creature_id"] for link in links)

        symbols.append(entry)

    # bridger domains with no jawnomicon symbol row: the 180 the atlas gains.
    for domain in domains:
        if domain["id"] in matched_domains:
            continue
        entry = {
            "slug": "bridger-" + domain["id"],
            "name": domain["title"],
            "register": "domain",
            "gloss": None,
            "attestations": None,
            "in": ["bridger"],
            "domain": {
                "id": domain["id"],
                "title": domain["title"],
                "world": domain["world"],
                "sub": domain["sub"],
                "sense_count": len(domain.get("senses") or []),
                "furniture_count": len(domain.get("furniture") or []),
                "sources": domain.get("sources") or [],
            },
        }
        if tier == "full":
            entry["domain"]["senses"] = domain.get("senses") or []
            entry["domain"]["furniture"] = domain.get("furniture") or []
        symbols.append(entry)

    symbols.sort(key=lambda s: norm(s["name"]))

    creatures = [
        creature_card(jaw["creatures"][cid], tier)
        for cid in sorted(linked_creature_ids)
        if cid in jaw["creatures"]
    ]

    both = sum(1 for s in symbols if len(s["in"]) == 2)
    return {
        "manifest": {
            "schema": "babelon-symbol-atlas/1",
            "tier": tier,
            "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
            "sources": {
                "jawnomicon": {
                    "export": jaw["manifest"].get("export_version"),
                    "canon_commit": jaw["manifest"].get("canon_commit"),
                    "repo_commit": git_commit(jaw_root),
                },
                "bridger": {"repo_commit": git_commit(bri_root)},
            },
            "counts": {
                "symbols": len(symbols),
                "in_both": both,
                "jawnomicon_only": sum(1 for s in symbols if s["in"] == ["jawnomicon"]),
                "bridger_only": sum(1 for s in symbols if s["in"] == ["bridger"]),
                "with_creatures": sum(1 for s in symbols if s.get("creatures")),
                "creatures": len(creatures),
            },
        },
        "symbols": symbols,
        "creatures": creatures,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--jawnomicon", type=pathlib.Path, default=pathlib.Path("/home/user/jawnomicon"))
    parser.add_argument("--bridger", type=pathlib.Path, default=pathlib.Path("/home/user/bridger"))
    parser.add_argument("--export", type=pathlib.Path,
                        help="bestiary.json (default: newest exports/v*/bestiary.json)")
    parser.add_argument("--tier", choices=("structure", "full"), default="structure")
    parser.add_argument("--out", type=pathlib.Path, default=pathlib.Path("symbol-atlas.json"))
    args = parser.parse_args()

    export = args.export
    if export is None:
        versions = sorted(
            (args.jawnomicon / "exports").glob("v*/bestiary.json"),
            key=lambda p: int(re.sub(r"\D", "", p.parent.name) or 0),
        )
        if not versions:
            print("no jawnomicon export found", file=sys.stderr)
            return 2
        export = versions[-1]

    atlas = build(args.jawnomicon, args.bridger, export, args.tier)
    args.out.write_text(json.dumps(atlas, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    counts = atlas["manifest"]["counts"]
    print(f"{args.out} ({args.out.stat().st_size // 1024} KB) tier={args.tier}")
    print(f"  symbols          {counts['symbols']}")
    print(f"    in both        {counts['in_both']}")
    print(f"    jawnomicon only{counts['jawnomicon_only']:>4}")
    print(f"    bridger only   {counts['bridger_only']}")
    print(f"  with creatures   {counts['with_creatures']} symbols, {counts['creatures']} creatures")
    if args.tier == "full":
        print("  NOTE: tier=full ships senses/furniture extracted from Cooper,")
        print("        de Vries and ARAS. Not for CC0 redistribution.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
