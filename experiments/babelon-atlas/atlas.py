#!/usr/bin/env python3
"""Read the symbol atlas, and watch Babelon's rooms for convergence.

  atlas.py symbol rainbow
  atlas.py search mirror
  atlas.py seed --world "Creation and Cosmos"
  atlas.py convergence path/to/invisible-rooms/rooms

`convergence` is the one that earns its place. Opus 5's rule for the trial is
that a room must state a mechanism, because moods are why twenty rooms turn into
one room. This measures that directly: which words and images the rooms already
share, and how fast the shared vocabulary is growing. It reads only the rooms
you point it at -- it needs no atlas, and Babelon's rooms are CC0.
"""

from __future__ import annotations

import argparse
import collections
import json
import pathlib
import random
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
DEFAULT_ATLAS = HERE / "symbol-atlas.json"

FIELD = re.compile(r"\*\*(MECHANISM|ACTION|CONSEQUENCE|DISCOVERABLE TEXT|THE CITY)\*\*\s*[-—]*\s*",
                   re.IGNORECASE)
WORD = re.compile(r"[a-z][a-z'-]{3,}")

# Function words plus the trial's own vocabulary: a room is not converging with
# another room because both say "room".
STOP = set("""
about above across after against along among around because before behind below
beneath beside between beyond both came come could does done down during each
either else even ever every from have having here hers herself him himself his
into itself just like made make many more most much must never next nothing once
only other others ours ourselves over same should since some such than that their
theirs them themselves then there these they this those through under until upon
very well were what when where which while whom whose will with within without
would your yours yourself
room rooms city cities visitor visitors text texts action consequence mechanism
discoverable archive archived place places thing things walk walks walked one
another each other people person
""".split())


def load_atlas(path: pathlib.Path) -> dict:
    if not path.is_file():
        sys.exit(f"no atlas at {path} — run build_atlas.py first")
    return json.loads(path.read_text(encoding="utf-8"))


def find(atlas: dict, needle: str) -> dict | None:
    key = re.sub(r"[^a-z0-9]", "", needle.lower())
    for symbol in atlas["symbols"]:
        if re.sub(r"[^a-z0-9]", "", symbol["name"].lower()) == key or symbol["slug"] == needle:
            return symbol
    return None


def creature_by_id(atlas: dict, cid: str) -> dict | None:
    return next((c for c in atlas["creatures"] if c["id"] == cid), None)


def show(atlas: dict, symbol: dict, verbose: bool = True) -> None:
    print(f"{symbol['name']}  [{symbol['register']}]  in: {', '.join(symbol['in'])}")
    if symbol.get("gloss"):
        print(f"  {symbol['gloss']}")
    if symbol.get("attestations"):
        print(f"  attested in {symbol['attestations']} sources")
    domain = symbol.get("domain")
    if domain:
        print(f"  domain: {domain['world']} › {domain['sub']}")
        print(f"    {domain['sense_count']} senses, {domain['furniture_count']} furniture objects"
              f"  ({', '.join(domain['sources'])})")
        for label in ("senses", "furniture"):
            if verbose and domain.get(label):
                items = domain[label]
                print(f"    {label}: {', '.join(items[:12])}"
                      + (f" … +{len(items) - 12}" if len(items) > 12 else ""))
    for link in symbol.get("creatures") or []:
        creature = creature_by_id(atlas, link["id"])
        name = creature["name"] if creature else link["id"]
        print(f"  creature: {name} ({link['status']}) — \"{link['evidence']}\"")
        if creature and verbose and creature.get("motifs"):
            print(f"    motifs: {', '.join(creature['motifs'][:8])}")


def cmd_symbol(args) -> int:
    atlas = load_atlas(args.atlas)
    symbol = find(atlas, args.name)
    if not symbol:
        print(f"no symbol {args.name!r}; try: atlas.py search {args.name}")
        return 1
    show(atlas, symbol)
    return 0


def cmd_search(args) -> int:
    atlas = load_atlas(args.atlas)
    needle = args.query.lower()
    hits = [
        s for s in atlas["symbols"]
        if needle in s["name"].lower() or needle in (s.get("gloss") or "").lower()
    ]
    print(f"{len(hits)} hit(s)")
    for symbol in hits[:args.limit]:
        marker = "+" if len(symbol["in"]) == 2 else " "
        gloss = (symbol.get("gloss") or "").split(".")[0][:90]
        print(f" {marker} {symbol['name']:<28} {gloss}")
    if len(hits) > args.limit:
        print(f"   … +{len(hits) - args.limit} more")
    return 0


def cmd_seed(args) -> int:
    """Draw a room seed: a symbol with furniture, and an inhabitant if it has one."""
    atlas = load_atlas(args.atlas)
    pool = [s for s in atlas["symbols"] if s.get("domain")]
    if args.world:
        pool = [s for s in pool if s["domain"]["world"].lower().startswith(args.world.lower())]
    if args.linked:
        pool = [s for s in pool if s.get("creatures")]
    if not pool:
        print("no symbol matches that filter")
        return 1
    rng = random.Random(args.seed)
    for symbol in rng.sample(pool, min(args.count, len(pool))):
        show(atlas, symbol)
        print()
    return 0


def parse_room(path: pathlib.Path) -> dict:
    text = path.read_text(encoding="utf-8")
    meta = {}
    if text.startswith("---"):
        end = text.find("\n---", 3)
        block, text = text[3:end], text[end + 4:]
        for line in block.strip().splitlines():
            if ":" in line:
                k, v = line.split(":", 1)
                meta[k.strip()] = v.strip()
    fields, current = {}, None
    for chunk in FIELD.split(text):
        if chunk.upper() in ("MECHANISM", "ACTION", "CONSEQUENCE", "DISCOVERABLE TEXT", "THE CITY"):
            current = chunk.upper()
        elif current:
            fields[current] = chunk.strip()
            current = None
    return {"slug": path.stem, "meta": meta, "fields": fields, "text": text}


def cmd_convergence(args) -> int:
    rooms_dir = args.rooms
    paths = sorted(p for p in rooms_dir.glob("*.md") if p.stem != "TEMPLATE")
    if not paths:
        sys.exit(f"no rooms in {rooms_dir}")
    rooms = [parse_room(p) for p in paths]

    use: dict[str, set[str]] = collections.defaultdict(set)
    for room in rooms:
        body = room["fields"].get("THE CITY", room["text"]).lower()
        for word in set(WORD.findall(body)):
            if word not in STOP:
                use[word].add(room["slug"])

    n = len(rooms)
    shared = sorted(
        ((w, sorted(r)) for w, r in use.items() if len(r) > 1),
        key=lambda item: (-len(item[1]), item[0]),
    )
    everywhere = [(w, r) for w, r in shared if len(r) == n]

    print(f"{n} rooms: {', '.join(r['slug'] for r in rooms)}")
    print(f"{len(shared)} words shared by 2+ rooms; {len(everywhere)} in every room")
    print()
    print("Shared vocabulary — the tic watch")
    for word, where in shared[:args.limit]:
        print(f"  {len(where)}/{n}  {word:<18} {', '.join(where)}")
    print()

    print("Mechanism check — one sentence a builder could implement")
    for room in rooms:
        mech = " ".join((room["fields"].get("MECHANISM") or "").split())
        if not mech:
            print(f"  {room['slug']:<12} MISSING")
            continue
        sentences = len([s for s in re.split(r"(?<=[.!?])\s+", mech) if s.strip()])
        flag = "" if sentences == 1 else f"  <- {sentences} sentences"
        print(f"  {room['slug']:<12} {len(mech.split()):>3}w{flag}")

    missing = [
        (room["slug"], field)
        for room in rooms
        for field in ("MECHANISM", "ACTION", "CONSEQUENCE", "DISCOVERABLE TEXT", "THE CITY")
        if not room["fields"].get(field)
    ]
    if missing:
        print()
        print("Incomplete rooms")
        for slug, field in missing:
            print(f"  {slug}: no {field}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--atlas", type=pathlib.Path, default=DEFAULT_ATLAS)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("symbol", help="look up one symbol")
    p.add_argument("name")
    p.set_defaults(func=cmd_symbol)

    p = sub.add_parser("search", help="search names and glosses")
    p.add_argument("query")
    p.add_argument("--limit", type=int, default=20)
    p.set_defaults(func=cmd_search)

    p = sub.add_parser("seed", help="draw a room seed")
    p.add_argument("--world")
    p.add_argument("--count", type=int, default=1)
    p.add_argument("--seed", type=int)
    p.add_argument("--linked", action="store_true", help="only symbols with a creature")
    p.set_defaults(func=cmd_seed)

    p = sub.add_parser("convergence", help="tic watch over a rooms/ directory")
    p.add_argument("rooms", type=pathlib.Path)
    p.add_argument("--limit", type=int, default=25)
    p.set_defaults(func=cmd_convergence)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
