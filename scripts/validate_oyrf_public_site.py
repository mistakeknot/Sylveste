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
CLOSED_LOOP = DOCS / "live" / "closed-loop.md"
FONT_DIR = DOCS / "fonts"
FONT_FILES = [
    FONT_DIR / "IoskeleyMono-Light.woff2",
    FONT_DIR / "IoskeleyMono-Regular.woff2",
    FONT_DIR / "IoskeleyMono-Bold.woff2",
]
REQUIRED = [INDEX, LIVE, CNAME, NOJEKYLL, ROBOTS, RUNBOOK, CLOSED_LOOP, *FONT_FILES]
LOCKED_HERO = "Sylveste coordinates software-development agents."
FORBIDDEN_PUBLIC_TERMS = ["Garden Salon", "Meadowsyn", "Mythos"]


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
    closed_loop = read(CLOSED_LOOP, failures)
    cname = read(CNAME, failures).strip()
    robots = read(ROBOTS, failures)
    runbook = read(RUNBOOK, failures)

    if LOCKED_HERO not in index:
        fail("landing page must include the locked Sylveste hero claim", failures)
    if "Sylveste%20launch%20list" in index or "Launch list" in index:
        fail("landing page must not expose the removed launch-list capture path", failures)
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
    if "sylveste.pages.dev" not in runbook or "Proxied" not in runbook:
        fail("deployment runbook must preserve the Cloudflare Pages DNS target", failures)
    if "launch list" in runbook.lower() or "subscriber test" in runbook.lower():
        fail("deployment runbook must not preserve the removed launch-list/email-provider blocker", failures)

    public_text = "\n".join([index, live, closed_loop, runbook])
    for term in FORBIDDEN_PUBLIC_TERMS:
        if re.search(rf"\b{re.escape(term)}\b", public_text, flags=re.IGNORECASE):
            fail(f"public site source must not mention held/private term: {term}", failures)


def validate_git_visibility(failures: list[str]) -> None:
    for rel in ["docs/index.html", "docs/live/index.html", "docs/live/closed-loop.md", "docs/CNAME", "docs/.nojekyll", "docs/robots.txt", "docs/deploy/sylvst-com.md", "docs/fonts/IoskeleyMono-Light.woff2", "docs/fonts/IoskeleyMono-Regular.woff2", "docs/fonts/IoskeleyMono-Bold.woff2"]:
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
