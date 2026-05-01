# sylvst.com deployment runbook

Bead: `sylveste-oyrf.2`

This page records the public launch deployment seam for `sylvst.com`.

## Source

The static public surface is intentionally small and lives under `docs/` so GitHub Pages can serve it without exposing private runtime state:

- `docs/index.html` — landing page
- `docs/live/index.html` — public closed-loop telemetry view
- `docs/CNAME` — custom-domain declaration for `sylvst.com`
- `docs/.nojekyll` — serve static files directly
- `docs/robots.txt` — public indexing posture

The live view reads the public CSV from the repository raw URL:

```text
https://raw.githubusercontent.com/mistakeknot/Sylveste/main/data/cost-trajectory.csv
```

It does not read private Interstat data, prompts, local session logs, Dolt state, or credentials.

## GitHub Pages

Configure Pages for the `mistakeknot/Sylveste` repository:

- branch: `main`
- path: `/docs`
- custom domain: `sylvst.com`

If configuring through the GitHub API, use a GitHub token with repository administration rights. Do not commit the token or write it into this repository.

## Cloudflare DNS

`docs/CNAME` only tells GitHub Pages what custom domain to expect. Cloudflare still needs DNS records for `sylvst.com`.

Use the Cloudflare zone for `sylvst.com` and GitHub Pages' current apex-domain guidance. At the time of writing, GitHub Pages supports apex domains through A/AAAA records and recommends verifying the domain before relying on it.

After DNS is configured, verify:

```bash
dig +short sylvst.com
curl -I https://sylvst.com
curl -fsSL https://sylvst.com/ | grep -F 'Sylveste orchestrates agents by human/machine comparative advantage.'
curl -fsSL https://sylvst.com/live/ | grep -F 'Closed-loop telemetry'
```
