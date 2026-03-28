# Dotfiles Management with yadm

Host-conditional dotfiles using [yadm](https://yadm.io) — manages `~/.claude/` configs with per-hostname alternates.

## How it works

yadm is a git wrapper that adds **alternate files** — files suffixed with `##h.<hostname>` that auto-link based on the current machine's hostname.

```
~/.claude/CLAUDE.md              # shared across all machines (includes @host.md)
~/.claude/host.md##h.Clavain    # deployed as host.md on Clavain (laptop)
~/.claude/host.md##h.sleeper-service  # deployed as host.md on sleeper-service
~/.claude/host.md → host.md##h.Clavain  # symlink created by `yadm alt`
```

CLAUDE.md contains `@host.md` which Claude Code resolves to the symlinked host-specific file.

## Machines

| Hostname | `hostname -s` | Role |
|----------|--------------|------|
| Clavain.local | `Clavain` | M5 Max laptop — runs interfere inference server |
| sleeper-service | `sleeper-service` | Build/backup server — remote inference client, Oracle |

## Setup on a new machine

```bash
# Install yadm
brew install yadm        # macOS
sudo apt install yadm    # Ubuntu/Debian

# Clone the dotfiles repo
yadm clone <REPO_URL>

# yadm automatically runs `alt` after clone — creates host symlinks
# Verify:
ls -la ~/.claude/host.md
# Should show: host.md -> host.md##h.<your-hostname>
```

## Adding a new machine

1. Create the host-specific file:
   ```bash
   vim ~/.claude/host.md##h.<new-hostname>
   ```

2. Add and commit:
   ```bash
   yadm add ~/.claude/host.md##h.<new-hostname>
   yadm commit -m "Add host config for <new-hostname>"
   yadm push
   ```

3. On the new machine, `yadm pull && yadm alt` creates the symlink.

## Adding more dotfiles

```bash
# Track any file in your home directory
yadm add ~/.config/some-tool/config.yaml
yadm commit -m "Add some-tool config"

# Host-specific version:
# Create ~/.config/some-tool/config.yaml##h.Clavain
# Create ~/.config/some-tool/config.yaml##h.sleeper-service
yadm add ~/.config/some-tool/config.yaml##h.Clavain
yadm add ~/.config/some-tool/config.yaml##h.sleeper-service
yadm commit -m "Add host-specific some-tool configs"
```

## Interaction with mutagen

mutagen syncs `~/projects/` bidirectionally between Clavain and sleeper-service. yadm manages `~/` (home directory files like `~/.claude/`). They operate on different paths and don't conflict.

**However**: if mutagen also syncs `~/.claude/`, you'll get conflicts because yadm creates symlinks that mutagen may not handle well. Options:
- Exclude `~/.claude/` from mutagen sync and let yadm manage it on both machines independently
- Keep mutagen syncing `~/.claude/` but don't use yadm alternates for those files (just use yadm as version control)

Current setup: mutagen syncs `~/.claude/` — yadm adds version control and the alternate mechanism on top. If symlink conflicts arise, exclude `~/.claude/host.md*` from mutagen.

## yadm repo location

```
~/.local/share/yadm/repo.git    # bare git repo
```

## Useful commands

```bash
yadm status          # what's changed
yadm diff            # show changes
yadm add <file>      # track a file
yadm commit          # commit
yadm push/pull       # sync with remote
yadm alt             # re-create hostname symlinks
yadm list            # show all tracked files
yadm encrypt         # encrypt sensitive files (needs gpg setup)
```
