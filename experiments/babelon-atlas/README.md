# babelon-atlas

One read-only atlas joining **jawnomicon**'s symbol tier to **bridger**'s symbol-domain
registry, plus a CLI and an MCP server over it, so agents building on
[Babelön / Invisible Rooms](https://gitlab.com/ai-village-agents/open-chat/invisible-rooms)
can use both corpora without either graph database, either private repo, or the tailnet.

Staged here because this session could only push to Sylveste. The built
`symbol-atlas.json` is deliberately **not committed** — Sylveste is public, and whether
this data is published anywhere is an open question (see gate 1). **It belongs in
`jawnomicon`** (it reads that repo's published export and extends its symbol tier);
nothing in it is Sylveste-specific, and the directory moves as-is.

## What the join actually found

jawnomicon does not need to import a symbol tier — **it already has one.** Export v33
ships 950 symbols with original glosses and 114 evidence-cited creature links, held in
the export layer, out of canon and out of the relatedness universe. So this is a
reconciliation, not an import:

| | count |
|---|---:|
| symbols in the atlas | 1,130 |
| in both corpora | 133 |
| jawnomicon only | 817 |
| bridger only | **180** |
| symbols carrying a creature | 29 (105 creatures) |

The 180 bridger-only domains are the real gain, and they are not marginal — `Sun`,
`Moon`, `Fire`, `Tree`, `Ocean`, `Stone`, `Mountain`, `Mirror`. (Aventurina, the mirror
room, sits on a domain jawnomicon does not have.) In the other direction jawnomicon
brings 817 symbols bridger has never seen, each with a paraphrase gloss and a source
count, plus the creature layer bridger has no equivalent of.

## Three gates, none of them code

**1. Provenance — the reason there are two tiers.** bridger's `senses[]` and
`furniture[]` are phrases extracted from Cooper, de Vries and ARAS; jawnomicon's
contract (`docs/symbol-tier-design-question.md`, constraint 6) is *"extracted source
text never ships; glosses are original paraphrase."* Babelön is CC0.

- `--tier structure` (default) ships taxonomy labels, sense and furniture **counts**,
  motif labels, creature names, and jawnomicon's own glosses. No third-party text.
  `test_atlas.py` enforces this rather than asserting it.
- `--tier full` adds the extracted `senses[]`/`furniture[]` and creature prose. Useful
  privately; **not CC0-redistributable**.

Whether even the structure tier goes to a CC0 repo is an ownership call, not a
technical one. Nothing here has been published anywhere.

**2. Reachability.** jawnomicon's Neo4j is on a private network and bridger's CanonGraph
profile is local to the workstation; AI Village agents can reach neither. That is why the unit of exchange
is a built JSON file plus a reader, not a hosted server — and it matches how Babelön
itself works: static pages, no backend, `build.py` and a hand-written engine.

**3. jawnomicon-nhe.3 is still open.** How symbols get vectored and placed is explicitly
undecided, with seven measured constraints — the covariance gate, the hygiene-09
V-shrinkage lesson, and the strict 29-key creature schema all break if 308 domains are
merged into canon or into the relatedness universe. **This tool touches neither.** It
reads the published export and joins alongside it, which is the one place the symbol
tier already lives. It also supplies evidence for that question: bridger models a symbol
as a domain with furniture and rooms that realise it — a symbol as a *relation between
concrete things*, which is option "symbol as edge, not vector node" with a working
implementation behind it.

## Use

```bash
python3 build_atlas.py --jawnomicon ~/projects/jawnomicon --bridger ~/projects/bridger
python3 atlas.py symbol rainbow
python3 atlas.py search mirror
python3 atlas.py seed --linked --world "Creation and Cosmos"
python3 atlas.py convergence path/to/invisible-rooms/rooms
python3 test_atlas.py    # or: pytest test_atlas.py
```

MCP (stdio, standard library only, same wire style as bridger's `mcp/server.py`):

```json
{"mcpServers": {"babelon-atlas": {
  "command": "python3",
  "args": ["/path/to/babelon-atlas/mcp_server.py"],
  "env": {"BABELON_ATLAS": "/path/to/symbol-atlas.json",
          "BABELON_ROOMS": "/path/to/invisible-rooms/rooms"}}}}
```

Tools: `symbol_lookup` · `symbol_search` · `room_seed` · `convergence`.

## `convergence` is the one to give them first

Opus 5's rule for the trial is that a room must state a mechanism, *because moods are why
twenty rooms turn into one room.* `convergence` measures that drift directly — shared
vocabulary breadth across the rooms, and a per-room check that the mechanism is present
and is one sentence. It reads only the rooms directory, needs no atlas, and Babelön's
rooms are CC0, so it can be handed over with no provenance question at all.

At four rooms the reading is healthy: 29 words shared by two or more rooms, exactly one
word in all four (`cannot` — which is not a tic but a shared move; every room is built on
something a visitor is refused), and all four mechanisms present and single-sentence.

The natural next step, if the trial grows: run it per wave and let the shared-vocabulary
count be the signal for when the rooms need a new conceit rather than another room.
