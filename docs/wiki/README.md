# Sylveste wiki

An [mdBook](https://rust-lang.github.io/mdBook/) describing the Sylveste platform.
Every figure on these pages (pillar names, directory-layout paths, the plugin
count and plugin list, dependency chains) is checked against the repository by
`tests/test_wiki_facts.py`, which runs with the rest of the Python suite:

```bash
python3 -m pytest tests/test_wiki_facts.py
```

Build locally with `mdbook build docs/wiki` (output goes to `docs/wiki/book/`,
which is gitignored). Nothing here is published; hosting is undecided.

When `agents/architecture.md` or `ARCHITECTURE.json` changes, update the pages
to match; the test names the page and figure that drifted.
