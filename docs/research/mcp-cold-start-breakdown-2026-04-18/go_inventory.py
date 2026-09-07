import json
go_servers = [
    ("interlab", "interlab-mcp-src", "/home/mk/projects/Sylveste/interverse/interlab/bin/interlab-mcp"),
    ("interlock", "interlock-mcp-src", "/home/mk/projects/Sylveste/interverse/interlock/bin/interlock-mcp"),
    ("intermap", "intermap-mcp-src", "/home/mk/projects/Sylveste/interverse/intermap/bin/intermap-mcp"),
    ("intermux", "intermux-mcp-src", "/home/mk/projects/Sylveste/interverse/intermux/bin/intermux-mcp"),
]
records = []
for plugin, name, binpath in go_servers:
    records.append({
        "marketplace": "source-tree",
        "plugin": plugin,
        "version": "source",
        "source": binpath,
        "server_name": name,
        "type": "stdio",
        "command": binpath,
        "args": [],
        "url": None,
        "env": {},
        "headers": {},
    })
# Merge with existing inventory
with open("inventory.dedup.json") as f: inv = json.load(f)
inv["servers"].extend(records)
with open("inventory.full.json", "w") as f: json.dump(inv, f, indent=2)
print(f"total: {len(inv['servers'])}")
