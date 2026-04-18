#!/usr/bin/env python3
"""Measure minimal interpreter startup cost — the 'language tax' baseline
that each MCP server pays before any MCP-specific code runs."""
import json
import subprocess
import time


BASELINES = [
    ("bash-noop", ["bash", "-c", "exit 0"]),
    ("python-noop", ["python3", "-c", "pass"]),
    ("node-noop", ["node", "-e", "0"]),
    ("uv-help", ["uv", "--help"]),
    ("uv-run-python-noop", ["uv", "run", "--quiet", "python", "-c", "pass"]),
    ("npx-help", ["npx", "--help"]),
    ("npx-tsx-noop", ["npx", "tsx", "--version"]),
]


def time_cmd(cmd, trials=3):
    samples = []
    for _ in range(trials):
        t0 = time.perf_counter()
        try:
            subprocess.run(cmd, capture_output=True, timeout=30)
        except Exception as e:
            return {"error": str(e)}
        samples.append((time.perf_counter() - t0) * 1000)
    return {
        "min_ms": round(min(samples), 2),
        "med_ms": round(sorted(samples)[len(samples)//2], 2),
        "max_ms": round(max(samples), 2),
        "trials": trials,
    }


def main():
    out = {}
    for label, cmd in BASELINES:
        print(f"# {label}: {' '.join(cmd)}", flush=True)
        out[label] = {"cmd": " ".join(cmd), **time_cmd(cmd)}
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
