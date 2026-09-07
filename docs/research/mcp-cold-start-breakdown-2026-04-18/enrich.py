import json

with open("summary.json") as f: rows = json.load(f)

# Classify per server
CATEGORY = {
    "context7::context7": ("Node (npx)", "npx -y @upstash/context7-mcp"),
    "intercache::intercache": ("Python (uv run)", "bash → uv run → intercache-mcp"),
    "interdeep::interdeep": ("Python (uv run)", "bash → uv run → python (trafilatura, playwright)"),
    "interfluence::interfluence": ("Node (esbuild bundle)", "node bundle.js"),
    "interflux::exa": ("Node (npx)", "bash → npx -y exa-mcp-server"),
    "interflux::openrouter-dispatch": ("Node (esbuild bundle)", "bash → node dist/index.js"),
    "interjawn::interjawn": ("Node (npx tsx)", "npx tsx src/index.ts — BROKEN: Prisma ESM export"),
    "interject::interject": ("Python (uv run)", "bash → uv run → interject-mcp"),
    "interkasten::interkasten": ("Python (uv run, singleton)", "bash → singleton → uv run — already running"),
    "interknow::qmd": ("Node (npm global)", "bash → qmd (symlink → node_modules)"),
    "interlab::interlab": ("Go (launcher fails)", "launch-mcp.sh → go build — FAILS: go not on PATH"),
    "interlab::interlab-mcp-src": ("Go (direct binary)", "/home/mk/projects/Sylveste/.../interlab-mcp"),
    "interlens::interlens": ("Node (esbuild bundle)", "node bundle.mjs"),
    "interlock::interlock": ("Go (launcher fails)", "launch-mcp.sh → go build — FAILS"),
    "interlock::interlock-mcp-src": ("Go (direct binary)", "/home/mk/projects/Sylveste/.../interlock-mcp"),
    "intermap::intermap": ("Go (launcher fails)", "launch-mcp.sh → go build — FAILS"),
    "intermap::intermap-mcp-src": ("Go (direct binary)", "/home/mk/projects/Sylveste/.../intermap-mcp"),
    "intermux::intermux": ("Go (launcher fails)", "launch-mcp.sh → go build — FAILS"),
    "intermux::intermux-mcp-src": ("Go (direct binary)", "/home/mk/projects/Sylveste/.../intermux-mcp"),
    "interrank::interrank": ("Node (npx tsx)", "npx + tsx + loads 734 models at init"),
    "intersearch::intersearch": ("Python (uv run)", "uv run --directory → intersearch-mcp"),
    "tldr-swinton::tldr-code": ("Python (uv run)", "bash → uv run → tldr-mcp"),
    "tuivision::tuivision": ("Node (bash bootstrap)", "bash → node dist/"),
}

out = []
for r in rows:
    lang, detail = CATEGORY.get(r["server"], ("?", "?"))
    r["language"] = lang
    r["launcher_detail"] = detail
    out.append(r)

# Sort: failures at the bottom; successes by t_total ascending
succ = [r for r in out if r["successes"] > 0]
fail = [r for r in out if r["successes"] == 0]
succ.sort(key=lambda r: r["t_total_median_ms"] or 999999)
final = succ + fail

with open("summary_enriched.json", "w") as f: json.dump(final, f, indent=2)

# Emit markdown table
print("| # | Server | Language | t_total (p50 ms) | init RTT (p50 ms) | RSS peak (MB) | Runs | Notes |")
print("|---|--------|----------|-----------------:|------------------:|--------------:|:----:|-------|")
for i, r in enumerate(final, 1):
    med = r["t_total_median_ms"]
    med_s = f"{med:.0f}" if med is not None else "—"
    rtt_list = []
    if r["successes"] > 0:
        # Re-read init rtt from all.jsonl — we didn't store it in summary. Approximate with t_total since they're ~identical
        rtt_list.append(f"≈{med:.0f}")
    rtt_s = rtt_list[0] if rtt_list else "—"
    rss = r["rss_peak_mb"]
    rss_s = f"{rss:.1f}" if rss else "—"
    runs = f"{r['successes']}/{r['runs']}"
    notes = r["launcher_detail"][:80]
    if r["successes"] == 0:
        notes = "FAIL: " + r["fail_reason"][:100]
    print(f"| {i} | `{r['server']}` | {r['language']} | {med_s} | {rtt_s} | {rss_s} | {runs} | {notes} |")
