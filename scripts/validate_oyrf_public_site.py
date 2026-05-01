#!/usr/bin/env python3
"""Validate the OYRF sylvst.com public-site source artifacts."""

from __future__ import annotations

import argparse
import re
import socket
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
INDEX = DOCS / "index.html"
LIVE = DOCS / "live" / "index.html"
CNAME = DOCS / "CNAME"
NOJEKYLL = DOCS / ".nojekyll"
ROBOTS = DOCS / "robots.txt"
RUNBOOK = DOCS / "deploy" / "sylvst-com.md"
REQUIRED = [INDEX, LIVE, CNAME, NOJEKYLL, ROBOTS, RUNBOOK]
LOCKED_HERO = "Sylveste orchestrates agents by human/machine comparative advantage."
FORBIDDEN_PUBLIC_TERMS = ["Garden Salon", "Meadowsyn"]


def fail(message: str, failures: list[str]) -> None:
    failures.append(message)


def read(path: Path, failures: list[str]) -> str:
    if not path.exists():
        fail(f"missing required file: {path.relative_to(ROOT)}", failures)
        return ""
    return path.read_text(encoding="utf-8")


def validate_source(failures: list[str]) -> None:
    for path in REQUIRED:
        if not path.exists():
            fail(f"missing required file: {path.relative_to(ROOT)}", failures)

    index = read(INDEX, failures)
    live = read(LIVE, failures)
    cname = read(CNAME, failures).strip()
    robots = read(ROBOTS, failures)
    runbook = read(RUNBOOK, failures)

    if LOCKED_HERO not in index:
        fail("landing page must include the locked Sylveste hero claim", failures)
    if "mailto:mk@generalsystemsventures.com?subject=Sylveste%20launch%20list" not in index:
        fail("landing page must expose the temporary public-safe launch-list capture path", failures)
    if "https://github.com/mistakeknot/Sylveste" not in index:
        fail("landing page must link to the public Sylveste source", failures)
    if "/live/" not in index:
        fail("landing page must link to /live/", failures)
    if "raw.githubusercontent.com/mistakeknot/Sylveste/main/data/cost-trajectory.csv" not in live:
        fail("live page must read the public repository CSV, not private Interstat state", failures)
    if "docs/live/closed-loop.md" not in live:
        fail("live page must link back to the source closed-loop template", failures)
    if cname != "sylvst.com":
        fail("docs/CNAME must be exactly sylvst.com", failures)
    if "Sitemap: https://sylvst.com/sitemap.xml" not in robots:
        fail("robots.txt should declare the sylvst.com sitemap location", failures)
    if "Before closing the bead as fully complete" not in runbook:
        fail("deployment runbook must preserve the durable email-provider closeout blocker", failures)

    public_text = "\n".join([index, live])
    for term in FORBIDDEN_PUBLIC_TERMS:
        if term in public_text:
            fail(f"public landing/live HTML must not mention held brand: {term}", failures)


def validate_git_visibility(failures: list[str]) -> None:
    for rel in ["docs/index.html", "docs/live/index.html", "docs/CNAME", "docs/.nojekyll", "docs/robots.txt", "docs/deploy/sylvst-com.md"]:
        result = subprocess.run(
            ["git", "check-ignore", "-q", "--", rel],
            cwd=ROOT,
            text=True,
        )
        if result.returncode == 0:
            fail(f"{rel} is ignored by git", failures)


def validate_dns(failures: list[str]) -> None:
    try:
        socket.getaddrinfo("sylvst.com", 443)
    except socket.gaierror as exc:
        fail(f"sylvst.com does not currently resolve: {exc}", failures)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check-dns", action="store_true", help="also require sylvst.com to resolve")
    args = parser.parse_args()

    failures: list[str] = []
    validate_source(failures)
    validate_git_visibility(failures)
    if args.check_dns:
        validate_dns(failures)

    if failures:
        print("OYRF public site validation failed:")
        for item in failures:
            print(f"- {item}")
        return 1
    print("OYRF public site validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
