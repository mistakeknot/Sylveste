# About this wiki

The figures on these pages are verified by `tests/test_wiki_facts.py`:

- the six pillar names match the glossary in `agents/architecture.md`;
- the directory-layout table matches the module table in `agents/architecture.md`;
- the dependency-chain block matches the one in `agents/architecture.md`;
- the plugin count and the plugin table (names, versions, capability counts) match `ARCHITECTURE.json`;
- every page in `src/SUMMARY.md` exists, and every page is listed;
- no page contains absolute home-directory paths, private hostnames or internal ruling identifiers.

The wiki describes the repository as committed. Anything that depends on
the state of a particular machine is out of scope.
