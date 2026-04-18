import json
from statistics import median

records = []
with open("all.jsonl") as f:
    for line in f:
        records.append(json.loads(line))

# Per-server stats with actual init_rtt medians
per_server = {}
for r in records:
    key = r["server"]
    per_server.setdefault(key, []).append(r)

# Language map (copy from enrich.py)
LANGUAGE_MAP = {
    "context7::context7": "Node (npx)",
    "intercache::intercache": "Python (uv run)",
    "interdeep::interdeep": "Python (uv run)",
    "interfluence::interfluence": "Node (esbuild bundle)",
    "interflux::exa": "Node (npx)",
    "interflux::openrouter-dispatch": "Node (esbuild bundle)",
    "interject::interject": "Python (uv run)",
    "interknow::qmd": "Node (npm global)",
    "interlab::interlab-mcp-src": "Go (direct binary)",
    "interlens::interlens": "Node (esbuild bundle)",
    "interlock::interlock-mcp-src": "Go (direct binary)",
    "intermap::intermap-mcp-src": "Go (direct binary)",
    "intermux::intermux-mcp-src": "Go (direct binary)",
    "interrank::interrank": "Node (npx tsx)",
    "intersearch::intersearch": "Python (uv run)",
    "tldr-swinton::tldr-code": "Python (uv run)",
    "tuivision::tuivision": "Node (bash bootstrap)",
}

# Per-language aggregation
lang_buckets = {}
for srv, runs in per_server.items():
    lang = LANGUAGE_MAP.get(srv)
    if not lang: continue
    ok = [r for r in runs if r.get("response_ok")]
    if not ok: continue
    medt = median(r["t_total_ms"] for r in ok)
    medrtt = median(r["t_init_rtt_ms"] for r in ok)
    medrss = median(r["rss_peak_mb"] for r in ok)
    lang_buckets.setdefault(lang, []).append({"server": srv, "t": medt, "rtt": medrtt, "rss": medrss})

print("## Per-Server init_rtt Medians (ms)")
for srv, runs in sorted(per_server.items(), key=lambda kv: median([r["t_init_rtt_ms"] for r in kv[1] if r.get("response_ok")] or [999999])):
    ok = [r for r in runs if r.get("response_ok")]
    if not ok: continue
    mrtt = median(r["t_init_rtt_ms"] for r in ok)
    mtot = median(r["t_total_ms"] for r in ok)
    spawn = median(r["t_spawn_ms"] for r in ok)
    print(f"  {srv:40s}  spawn={spawn:6.2f}ms  init_rtt={mrtt:7.1f}ms  total={mtot:7.1f}ms")

print()
print("## Per-Language Aggregate")
print("| Language | Servers | p50 t_total (ms) | p50 RSS (MB) | Cumulative (ms) |")
print("|----------|--------:|-----------------:|-------------:|----------------:|")
for lang, items in sorted(lang_buckets.items(), key=lambda kv: median([i["t"] for i in kv[1]])):
    ts = [i["t"] for i in items]
    rs = [i["rss"] for i in items]
    print(f"| {lang} | {len(items)} | {median(ts):.0f} | {median(rs):.1f} | {sum(ts):.0f} |")
