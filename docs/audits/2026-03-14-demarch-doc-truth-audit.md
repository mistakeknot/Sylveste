# Sylveste Documentation Truth Audit

**Date:** 2026-03-14  
**Scope:** Sylveste root plus repos under `apps/`, `core/`, `os/`, `sdk/`, and `interverse/`  
**Method:** Deep review of canonical docs plus an exhaustive scan of remaining human-authored Markdown/context files

## Scope Summary

- 65 repos in scope (`root` + 64 first-level repos under `apps/`, `core/`, `os/`, `sdk/`, `interverse/`)
- 3,626 scoped docs scanned
- 678 canonical docs deep-audited or queued for canonical review
- 2,948 secondary docs inventory-scanned
- 587 broken Markdown links found in-scope
- 6,938 plain-text path flags found in-scope

**Exclusions:** generated and cache directories such as `.git/`, `.venv/`, `node_modules/`, `dist/`, `target/`, `.pytest_cache/`, and `.tldrs/`.

**Important caveat:** the broken Markdown link count is a direct signal; the plain-text path count is heuristic and should be treated as a hotspot indicator, not a defect count.

## Executive Summary

The documentation set is materially out of sync with repo reality in four recurring ways:

1. The root canon no longer agrees on what Sylveste is. After the Skaffen addition, some docs describe a five-pillar platform while others describe six pillars.
2. Case-sensitive path drift is widespread. Root and pillar docs still link to lowercase `os/clavain` and `apps/autarch` paths that do not exist on this filesystem.
3. Counts, status markers, and version strings are stale across both root docs and multiple subrepos.
4. The secondary-doc estate has significant link rot, especially in indexes, plans, and imported reference packs.

## High-Priority Findings

1. **Root architecture drift after Skaffen is now a canon-level contradiction.**  
   [docs/sylveste-vision.md:238](../sylveste-vision.md#L238) says Sylveste has six pillars and includes Skaffen; [docs/sylveste-reference.md:7](../sylveste-reference.md#L7) also defines a six-pillar model. But [docs/architecture.md:7](../architecture.md#L7), [docs/glossary.md:7](../glossary.md#L7), and [README.md:66](../../README.md#L66) still describe Sylveste as a five-pillar system. Repo reality supports the six-pillar version because `os/Skaffen` now exists as a first-level repo.

2. **The root canon has broken case-sensitive links to major pillar docs.**  
   [docs/architecture.md:135](../architecture.md#L135) and [docs/architecture.md:136](../architecture.md#L136) link to `os/clavain/...` and `apps/autarch/...`; those paths do not exist. The same lowercase drift appears in [docs/sylveste-vision.md:249](../sylveste-vision.md#L249) and [docs/sylveste-vision.md:299](../sylveste-vision.md#L299). These links only work if readers mentally correct the path casing.

3. **The root roadmap is stale both structurally and factually.**  
   [docs/sylveste-roadmap.md:3](../sylveste-roadmap.md#L3) still leaves module and bead totals as unevaluated shell commands instead of current values. The ecosystem table uses lowercase paths like [docs/sylveste-roadmap.md:69](../sylveste-roadmap.md#L69) and [docs/sylveste-roadmap.md:70](../sylveste-roadmap.md#L70), and it omits real top-level repos `interverse/interhelm`, `interverse/interlab`, and `sdk/interbase`. Live repo inventory is 64 first-level repos in those pillars, while live bead counts from `bd status --json` show 736 open issues.

4. **Kernel gate enforcement is overstated relative to the documented phase mapping.**  
   [docs/sylveste-vision.md:125](../sylveste-vision.md#L125) calls gates “kernel-enforced invariants,” but [docs/glossary.md:88](../glossary.md#L88) documents that OS-created sprints only get kernel gate coverage on 5 of 8 transitions because `plan-reviewed` and `shipping` diverge from kernel expectations. [docs/architecture.md:111](../architecture.md#L111) then describes the lifecycle as if the kernel simply walks the chain. The current wording hides a real enforcement gap.

5. **The root phase model is numerically inconsistent.**  
   [docs/architecture.md:111](../architecture.md#L111) says the OS configures a “10-phase sprint lifecycle,” but its own diagram at [docs/architecture.md:116](../architecture.md#L116) and [docs/architecture.md:117](../architecture.md#L117) shows 9 phases. [docs/glossary.md:74](../glossary.md#L74) correctly describes a 9-phase OS/kernel mapping.

6. **Intercom’s public story is obsolete and contradicts its own canonical docs.**  
   [apps/Intercom/README.md:18](../../apps/Intercom/README.md#L18), [apps/Intercom/README.md:52](../../apps/Intercom/README.md#L52), and [apps/Intercom/README.md:132](../../apps/Intercom/README.md#L132) still describe “NanoClaw,” WhatsApp-first flows, SQLite, and a Node-first architecture. That conflicts with [apps/Intercom/AGENTS.md:3](../../apps/Intercom/AGENTS.md#L3), [apps/Intercom/AGENTS.md:32](../../apps/Intercom/AGENTS.md#L32), and [apps/Intercom/CLAUDE.md:7](../../apps/Intercom/CLAUDE.md#L7), which describe Rust `intercomd`, Telegram-first mode, and Postgres-backed orchestration.

7. **Autarch’s canonical docs disagree on product scope and ship with broken navigation.**  
   [apps/Autarch/README.md:3](../../apps/Autarch/README.md#L3) and [apps/Autarch/docs/autarch-vision.md:18](../../apps/Autarch/docs/autarch-vision.md#L18) define Autarch as Bigend, Gurgeh, Coldwine, and Pollard. But [apps/Autarch/CLAUDE.md:12](../../apps/Autarch/CLAUDE.md#L12) and [apps/Autarch/CLAUDE.md:51](../../apps/Autarch/CLAUDE.md#L51) elevate `Mycroft` to a first-class tool. In parallel, [apps/Autarch/AGENTS.md:70](../../apps/Autarch/AGENTS.md#L70) links to a missing `docs/VISION.md`, and [apps/Autarch/docs/autarch-vision.md:41](../../apps/Autarch/docs/autarch-vision.md#L41) and [apps/Autarch/docs/autarch-vision.md:74](../../apps/Autarch/docs/autarch-vision.md#L74) link to files that do not exist.

8. **Clavain’s canonical docs repeat stale structural counts and one broken command path.**  
   [os/Clavain/README.md:5](../../os/Clavain/README.md#L5), [os/Clavain/CLAUDE.md:7](../../os/Clavain/CLAUDE.md#L7), and [os/Clavain/AGENTS.md:34](../../os/Clavain/AGENTS.md#L34) all say Clavain has `10 hooks`, but the repo currently has 23 top-level hook scripts under `os/Clavain/hooks/`. [os/Clavain/CLAUDE.md:13](../../os/Clavain/CLAUDE.md#L13) also tells users to run `claude --plugin-dir /home/mk/projects/Sylveste/os/clavain`, which is wrong on this filesystem.

9. **Several interverse repos have direct status or architecture contradictions in canonical docs.**  
   [interverse/interserve/docs/interserve-vision.md:1](../../interverse/interserve/docs/interserve-vision.md#L1) and [interverse/interserve/README.md:1](../../interverse/interserve/README.md#L1) still present interserve as active, while [interverse/interserve/DEPRECATED.md:1](../../interverse/interserve/DEPRECATED.md#L1) marks it deprecated as of 2026-03-01.  
   [interverse/interphase/README.md:39](../../interverse/interphase/README.md#L39) documents a `lib/` tree that no longer exists.  
   [interverse/interstat/README.md:45](../../interverse/interstat/README.md#L45) still describes a two-hook architecture, but the repo now ships five hook scripts.

10. **Version and command-count drift is widespread in canonical module docs.**  
    [interverse/interspect/README.md:45](../../interverse/interspect/README.md#L45) says 12 commands, [interverse/interspect/CLAUDE.md:7](../../interverse/interspect/CLAUDE.md#L7) says 14, but `interverse/interspect/commands/` currently contains 15 command files.  
    Stale version markers also exist in [interverse/intersearch/docs/intersearch-vision.md:3](../../interverse/intersearch/docs/intersearch-vision.md#L3), [interverse/interstat/docs/interstat-vision.md:3](../../interverse/interstat/docs/interstat-vision.md#L3), [interverse/tldr-swinton/docs/tldr-swinton-vision.md:3](../../interverse/tldr-swinton/docs/tldr-swinton-vision.md#L3), [interverse/tldr-swinton/README.md:44](../../interverse/tldr-swinton/README.md#L44), and [interverse/tuivision/docs/tuivision-vision.md:3](../../interverse/tuivision/docs/tuivision-vision.md#L3) when compared against their manifests.

## Medium-Priority Findings

1. **Interspect’s kernel-boundary story is internally inconsistent.**  
   [docs/interspect-vision.md:24](../interspect-vision.md#L24) says Interspect never modifies the kernel and treats that as a mechanical constraint, while [PHILOSOPHY.md:104](../../PHILOSOPHY.md#L104) and [docs/sylveste-vision.md:69](../sylveste-vision.md#L69) describe the kernel boundary as a trust threshold that can soften. The current docs mix “never” language with “future-softenable” language without scoping the difference.

2. **sdk/interbase’s README understates the shipped SDK surface.**  
   [sdk/interbase/README.md:3](../../sdk/interbase/README.md#L3) describes only Bash and Go SDKs, while [sdk/interbase/AGENTS.md:25](../../sdk/interbase/AGENTS.md#L25) and [sdk/interbase/AGENTS.md:34](../../sdk/interbase/AGENTS.md#L34) already document Bash, Go, and Python SDKs.

3. **Secondary-doc link rot is concentrated in a small number of recurring hotspots.**  
   The worst current hotspot is [docs/solutions/INDEX.md](../solutions/INDEX.md), which still points at legacy path prefixes such as `infra/`, `hub/`, `plugins/`, and `services/` that no longer match the monorepo layout. Imported reference packs under `interverse/interdev/skills/working-with-claude-code/references/` are the next major cluster.

## Inventory Findings

- The automated scan found 587 broken Markdown links in-scope.
- The largest broken-link hotspot is [docs/solutions/INDEX.md](../solutions/INDEX.md), followed by the imported reference pack in `interverse/interdev`.
- The largest document estates by volume are the root repo, `os/Clavain`, `apps/Autarch`, `interverse/tldr-swinton`, `core/intercore`, `interverse/interject`, and `interverse/interflux`.
- The largest secondary-doc estates are concentrated in plans, research, and solution/reference directories rather than in canonical README/vision/roadmap surfaces.

## Recommended Remediation Order

1. Normalize the root model first: decide whether Sylveste is formally five pillars or six, then align `README.md`, `docs/architecture.md`, `docs/glossary.md`, `docs/sylveste-reference.md`, and `docs/sylveste-vision.md`.
2. Fix all root and pillar canonical links that use wrong-case paths or missing targets.
3. Replace shell-command placeholders in root roadmap/vision docs with actual evaluated counts and refresh the ecosystem snapshot from live repo state.
4. Rewrite the public-facing canonical docs for Intercom and Autarch so README, vision, AGENTS, and CLAUDE tell the same current story.
5. Sweep stale structural counts and version markers across Clavain and the affected interverse repos.
6. Regenerate or rewrite the high-rot indexes and imported reference packs, starting with `docs/solutions/INDEX.md`.
