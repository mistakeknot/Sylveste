#!/usr/bin/env python3
"""Extract trigger-vocabulary from a SKILL.md frontmatter description.

The Claude Code harness indexes skill matches against the `description:` field.
Trimming below the trigger-vocab threshold silently breaks discovery, so this
script captures the vocab snapshot BEFORE an edit for post-edit comparison
(see Task 3 / Step 2.5 of docs/plans/2026-04-21-sylveste-ynh7-skill-listing-compact.md).
"""
import json
import re
import sys


STOPWORDS = {"should", "skill", "where", "while", "across"}


def extract_description(text: str) -> str:
    if not text.startswith("---"):
        return ""
    end = text.find("---", 3)
    if end < 0:
        return ""
    for ln in text[3:end].splitlines():
        if ln.lstrip().startswith("description:"):
            return ln.split(":", 1)[1].strip().strip('"\'')
    return ""


def extract_vocab(desc: str) -> list[str]:
    vocab: set[str] = set()
    for m in re.finditer(r'"([^"]+)"', desc):
        for w in m.group(1).split():
            if len(w) > 3:
                vocab.add(w.lower().strip(',."-:'))
    for m in re.finditer(r"(?:use when|trigger when|when the user)[\s:]+([^.]+)", desc, re.I):
        for w in m.group(1).split():
            if len(w) > 3:
                vocab.add(w.lower().strip(',."-:'))
    for w in desc.split():
        w2 = w.lower().strip(',."-:')
        if len(w2) > 5 and w2 not in STOPWORDS:
            vocab.add(w2)
    vocab.discard("")
    return sorted(vocab)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: extract-trigger-vocab.py <SKILL.md>", file=sys.stderr)
        return 2
    path = sys.argv[1]
    desc = extract_description(open(path).read())
    print(json.dumps(extract_vocab(desc)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
