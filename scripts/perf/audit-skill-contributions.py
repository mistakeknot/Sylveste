#!/usr/bin/env python3
"""Audit per-plugin skill_listing byte contribution, cross-reference usage.

Reads SKILL.md files from plugins-root (default: ~/.claude/plugins), extracts
the frontmatter `description:` field, groups by plugin, and cross-references
MCP tool usage from ~/.claude/interstat/metrics.db. Emits JSON suitable for
driving disable decisions under sylveste-ynh7.
"""
import argparse
import glob
import json
import os
import sqlite3
from collections import defaultdict


def parse_frontmatter(text):
    if not text.startswith("---"):
        return {}
    end = text.find("---", 3)
    if end < 0:
        return {}
    out = {}
    for ln in text[3:end].splitlines():
        if ":" in ln:
            k, _, v = ln.partition(":")
            out[k.strip()] = v.strip()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--plugins-root", default=os.path.expanduser("~/.claude/plugins"))
    ap.add_argument("--db", default=os.path.expanduser("~/.claude/interstat/metrics.db"))
    ap.add_argument("--since-days", type=int, default=30)
    ap.add_argument("--out", default="-")
    args = ap.parse_args()

    # Dedup by (plugin, skill_name); prefer shortest path when multiple versions exist.
    # Path layouts:
    #   marketplaces/<m>/plugins/<plugin>/skills/<skill>/SKILL.md      ← preferred source
    #   cache/<hash>/.claude-plugin/skills/<skill>/SKILL.md            ← resolve via plugin.json
    #   cache/<marketplace>/<plugin>/<version>/skills/<skill>/SKILL.md ← cache of marketplace
    per_plugin = defaultdict(lambda: {"skills": 0, "desc_bytes": 0, "examples": []})
    seen = set()

    def resolve_plugin(path):
        parts = path.split("/")
        if "marketplaces" in parts:
            # .claude/plugins/marketplaces/<m>/plugins/<plugin>/skills/<skill>/SKILL.md
            # Two "plugins" segments exist; use the INNER one (marketplace's plugins dir)
            try:
                m_idx = parts.index("marketplaces")
                # Find the first "plugins" segment after "marketplaces"
                inner_plugins = parts.index("plugins", m_idx)
                return parts[inner_plugins + 1]
            except (ValueError, IndexError):
                pass
        if ".claude-plugin" in parts:
            # cache/<hash>/.claude-plugin/... → read plugin.json for the name
            claude_idx = parts.index(".claude-plugin")
            plugin_json = "/".join(parts[:claude_idx + 1]) + "/plugin.json"
            if os.path.exists(plugin_json):
                try:
                    return json.load(open(plugin_json)).get("name", "unknown")
                except Exception:
                    pass
            # Fallback: use the parent of .claude-plugin
            return parts[claude_idx - 1] if claude_idx > 0 else "unknown"
        if "cache" in parts:
            # cache/<marketplace>/<plugin>/<version>/skills/...
            try:
                i = parts.index("cache")
                # parts[i+1] = marketplace, parts[i+2] = plugin, parts[i+3] = version
                if len(parts) > i + 3 and parts[i + 4] == "skills":
                    return parts[i + 2]
                # Or structure is cache/<plugin>/<version>/skills/
                if len(parts) > i + 2 and parts[i + 3] == "skills":
                    return parts[i + 1]
            except (ValueError, IndexError):
                pass
        # Fallback: segment before "skills"
        try:
            return parts[parts.index("skills") - 1]
        except (ValueError, IndexError):
            return "unknown"

    # Sort so marketplace paths (shortest after resolver) come first — that way
    # subsequent cache paths with the same skill resolve to a dedup hit.
    all_paths = sorted(glob.glob(f"{args.plugins_root}/**/SKILL.md", recursive=True),
                       key=lambda p: (0 if "marketplaces" in p else 1, len(p)))
    for p in all_paths:
        plugin = resolve_plugin(p)
        skill_name = os.path.basename(os.path.dirname(p))
        # Skip pure-hash cache entries — these are always duplicates of resolved
        # plugin entries from the marketplace layout.
        if plugin.startswith("temp_git_"):
            continue
        key = (plugin, skill_name)
        if key in seen:
            continue
        seen.add(key)
        try:
            fm = parse_frontmatter(open(p).read())
        except Exception:
            continue
        desc = fm.get("description", "").strip().strip('"\'')
        per_plugin[plugin]["skills"] += 1
        per_plugin[plugin]["desc_bytes"] += len(desc)
        if len(per_plugin[plugin]["examples"]) < 3:
            per_plugin[plugin]["examples"].append(skill_name)

    # Usage: MCP calls + Skill invocations per plugin, last N days.
    # Stored lowercase since tool names may be capitalized (mcp__plugin_Notion_notion__...).
    usage = defaultdict(int)
    if os.path.exists(args.db):
        c = sqlite3.connect(args.db)
        cutoff = f"date('now','-{args.since_days} days')"
        rows = c.execute(
            f"""
            SELECT tool_name, COUNT(*) FROM tool_selection_events
            WHERE timestamp >= {cutoff}
            GROUP BY tool_name
            """
        ).fetchall()
        for tool, calls in rows:
            if not tool:
                continue
            if tool.startswith("mcp__plugin_"):
                rest = tool[len("mcp__plugin_"):]
                plugin = rest.split("__", 1)[0].split("_", 1)[0].lower()
                usage[plugin] += calls
            elif tool == "Skill":
                usage["_skill_invocations"] += calls

    # Workflow-critical plugins that would appear "cold" by MCP signal alone
    # (they use the Skill tool, not MCP). Hard-exclude from disable candidates.
    HARD_EXCLUDE = {
        "clavain", "interflux", "interspect", "intersearch", "interstat",
        "beads", "bd", "intermem", "interpath", "interwatch", "interdev",
    }

    rows = []
    for plugin, info in per_plugin.items():
        mcp_calls = usage.get(plugin.lower(), 0)
        is_hard_excluded = plugin.lower() in HARD_EXCLUDE
        rows.append(
            {
                "plugin": plugin,
                "skills": info["skills"],
                "desc_bytes": info["desc_bytes"],
                "mcp_calls_30d": mcp_calls,
                "examples": info["examples"],
                "hard_excluded": is_hard_excluded,
                "cold": (not is_hard_excluded) and mcp_calls < 5 and info["desc_bytes"] > 500,
            }
        )
    rows.sort(key=lambda r: -r["desc_bytes"])
    out = json.dumps(rows, indent=2)
    if args.out == "-":
        print(out)
    else:
        with open(args.out, "w") as f:
            f.write(out)


if __name__ == "__main__":
    main()
