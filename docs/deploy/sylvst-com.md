# sylvst.com deployment runbook

Bead: `sylveste-oyrf.2`

This page records the public deployment seam for `sylvst.com`.

## Source

The static public surface is intentionally small and lives under `docs/` so Cloudflare Pages can serve it without exposing private runtime state:

- `docs/index.html` — landing page
- `docs/live/index.html` — public closed-loop telemetry view
- `docs/live/closed-loop.md` — source template linked from the public telemetry page
- `docs/fonts/` — Ioskeley Mono font files copied from the GSV site source
- `docs/CNAME` — custom-domain declaration for `sylvst.com`
- `docs/.nojekyll` — static compatibility marker
- `docs/robots.txt` — public indexing posture

The live view reads the public CSV from the repository raw URL:

```text
https://raw.githubusercontent.com/mistakeknot/Sylveste/main/data/cost-trajectory.csv
```

It does not read private Interstat data, prompts, local session logs, Beads state, Dolt state, or credentials.

## Cloudflare Pages

Cloudflare Pages project:

- project: `sylveste`
- production branch: `main`
- public preview host: `sylveste.pages.dev`
- custom domain: `sylvst.com`

Deploy from a staged subset of `docs/` rather than the whole directory, because `docs/` also contains internal planning artifacts and symlinks that are not part of the public site.

## Cloudflare DNS

The apex DNS record should be:

```text
Type:   CNAME
Name:   sylvst.com
Target: sylveste.pages.dev
Proxy:  Proxied
TTL:    Auto
```

Cloudflare flattens the proxied apex CNAME. After DNS is configured, verify:

```bash
dig +short sylvst.com
curl -I https://sylvst.com
curl -fsSL https://sylvst.com/ | grep -F 'Sylveste coordinates software-development agents.'
curl -fsSL https://sylvst.com/live/ | grep -F 'Public cost and session trajectory.'
```
