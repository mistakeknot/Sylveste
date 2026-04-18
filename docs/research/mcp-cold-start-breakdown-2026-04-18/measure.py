#!/usr/bin/env python3
"""MCP cold-start timing harness. Spawns each launcher in isolation, sends
`initialize`, measures wall-time to response and RSS.

Outputs JSONL (one record per launcher-trial) to stdout.
"""
import json
import os
import select
import subprocess
import sys
import time
from pathlib import Path

INITIALIZE = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {"name": "cold-start-spike", "version": "0.1.0"},
    },
}


def resolve_plugin_root(source_path: str) -> str:
    """Given .../<plugin>/<version>/.claude-plugin/plugin.json OR .mcp.json,
    return .../<plugin>/<version>."""
    p = Path(source_path)
    if p.name == "plugin.json" and p.parent.name == ".claude-plugin":
        return str(p.parent.parent)
    if p.name == ".mcp.json":
        return str(p.parent)
    return str(p.parent)


def substitute(value, plugin_root):
    if isinstance(value, str):
        return value.replace("${CLAUDE_PLUGIN_ROOT}", plugin_root)
    if isinstance(value, list):
        return [substitute(v, plugin_root) for v in value]
    if isinstance(value, dict):
        return {k: substitute(v, plugin_root) for k, v in value.items()}
    return value


def read_rss_kb(pid: int):
    try:
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                if line.startswith("VmRSS:"):
                    return int(line.split()[1])
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        pass
    return None


def time_launcher(record, timeout=30.0):
    server_name = f"{record['plugin']}::{record['server_name']}"
    plugin_root = resolve_plugin_root(record["source"])
    cmd_str = substitute(record["command"], plugin_root)
    args = [a for a in substitute(record["args"], plugin_root) if a != ""]
    env_overlay = substitute(record["env"], plugin_root)
    # Split cmd (might be shebang + multiple tokens via shell splitting)
    if " " in cmd_str and not os.path.exists(cmd_str.split()[0]):
        # Attempt shell split
        cmd_parts = cmd_str.split()
    else:
        cmd_parts = [cmd_str]
    full_cmd = cmd_parts + args

    env = os.environ.copy()
    env["CLAUDE_PLUGIN_ROOT"] = plugin_root
    env.update({k: str(v) for k, v in env_overlay.items()})

    result = {
        "server": server_name,
        "plugin": record["plugin"],
        "server_name": record["server_name"],
        "command": cmd_str,
        "args": args,
        "plugin_root": plugin_root,
        "cmd_exec": full_cmd,
    }

    t0 = time.perf_counter()
    try:
        proc = subprocess.Popen(
            full_cmd,
            env=env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=0,
            cwd=plugin_root,
        )
    except FileNotFoundError as e:
        result["error"] = f"popen FileNotFoundError: {e}"
        return result
    except Exception as e:
        result["error"] = f"popen exception: {e}"
        return result

    result["pid"] = proc.pid
    t_spawn = time.perf_counter()

    # Send initialize
    try:
        proc.stdin.write((json.dumps(INITIALIZE) + "\n").encode())
        proc.stdin.flush()
    except (BrokenPipeError, OSError) as e:
        result["error"] = f"stdin write failed (server died): {e}"
        try:
            proc.kill()
        except ProcessLookupError:
            pass
        return result
    t_sent = time.perf_counter()

    # Read stdout line-by-line looking for initialize response
    deadline = t_sent + timeout
    response = None
    resp_buf = b""
    stderr_chunks = []
    peak_rss_during_boot = None
    rss_samples = []
    # Sample RSS a few times during boot
    last_rss_sample = 0

    while time.perf_counter() < deadline:
        now = time.perf_counter()
        if now - last_rss_sample > 0.05:
            rss = read_rss_kb(proc.pid)
            if rss:
                rss_samples.append((now - t0, rss))
            last_rss_sample = now

        ready, _, _ = select.select([proc.stdout, proc.stderr], [], [], 0.05)
        if proc.stdout in ready:
            chunk = proc.stdout.readline()
            if chunk:
                # MCP is line-delimited. Try each line independently — don't
                # accumulate across lines because wrapper scripts (npm, shell)
                # emit non-JSON banner output before the JSON-RPC response.
                line = chunk.decode(errors="replace").strip()
                if line:
                    try:
                        msg = json.loads(line)
                        if isinstance(msg, dict) and msg.get("id") == 1:
                            response = msg
                            break
                    except json.JSONDecodeError:
                        # Not JSON — probably wrapper banner. Record and move on.
                        stderr_chunks.append(b"[non-json stdout] " + chunk)
        if proc.stderr in ready:
            try:
                data = os.read(proc.stderr.fileno(), 4096)
                if data:
                    stderr_chunks.append(data)
            except OSError:
                pass

        if proc.poll() is not None and not response:
            result["error"] = f"process exited rc={proc.returncode} before response"
            break

    t_resp = time.perf_counter() if response else None

    # Capture final RSS
    final_rss_kb = read_rss_kb(proc.pid)
    if final_rss_kb:
        rss_samples.append((time.perf_counter() - t0, final_rss_kb))

    # Kill
    try:
        proc.terminate()
        try:
            proc.wait(timeout=0.5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=1.0)
    except Exception:
        pass

    result.update({
        "t_spawn_ms": round((t_spawn - t0) * 1000, 2),
        "t_total_ms": round((t_resp - t0) * 1000, 2) if t_resp else None,
        "t_init_rtt_ms": round((t_resp - t_sent) * 1000, 2) if t_resp else None,
        "rss_peak_mb": round(max((kb for _, kb in rss_samples), default=0) / 1024, 2) if rss_samples else None,
        "response_ok": response is not None,
        "initialize_result_keys": sorted(list(response.get("result", {}).keys())) if response else None,
        "stderr_tail": b"".join(stderr_chunks).decode(errors="replace")[-400:] if stderr_chunks else "",
    })
    if "error" not in result and not response:
        result["error"] = "timeout: no initialize response within {}s".format(timeout)
    return result


def main():
    inventory_path = sys.argv[1] if len(sys.argv) > 1 else "inventory.dedup.json"
    trials = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    with open(inventory_path) as f:
        data = json.load(f)
    for record in data["servers"]:
        if not record.get("command"):  # skip HTTP servers
            continue
        for trial in range(trials):
            out = time_launcher(record)
            out["trial"] = trial
            print(json.dumps(out), flush=True)


if __name__ == "__main__":
    main()
