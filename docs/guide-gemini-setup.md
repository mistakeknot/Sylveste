# Gemini CLI Setup Guide

**Time:** 5 minutes

**Prerequisites:**
- [Gemini CLI](https://github.com/google/gemini-cli) installed (`npm install -g @google/gemini-cli`)
- Git

## Fresh Install

Since Gemini CLI uses specialized `SKILL.md` instructions dynamically generated from the Interverse plugins, you should clone the `Sylveste` monorepo to your machine. This gives you a permanent location to sync upstream changes and generate skills from.

1. **Clone the Sylveste Repository**
   Choose a stable location (e.g., `~/projects` or `~/.gemini/sylveste`):
   ```bash
   git clone --recursive https://github.com/mistakeknot/Sylveste.git ~/.local/share/Sylveste
   cd ~/.local/share/Sylveste
   ```

2. **Run the Gemini Installer**
   This script will compile the phase documents into Gemini skills, generate Gemini slash-command wrappers from Sylveste `commands/*.md`, and link both globally:
   ```bash
   bash scripts/install-gemini-interverse.sh install
   ```

This generates all the required `SKILL.md` files locally, generates project commands in `~/.local/share/Sylveste/.gemini/commands`, registers the skills directory (`~/.local/share/Sylveste/.gemini/generated-skills`) to your global `~/.gemini/skills` directory, and symlinks each command namespace into `~/.gemini/commands`.

## Verify

Check that the skills are linked in the global scope:

```bash
gemini skills list --all
```

You should see `clavain`, `interdoc`, `tool-time`, `interflux`, and the rest of the Interverse companion skills in the list.

Check that the commands were generated:

```bash
find ~/.gemini/commands -maxdepth 2 -type f -name '*.toml' | rg 'clavain|interflux|interpath'
```

If Gemini is already running, use `/commands reload` to refresh command discovery without restarting the CLI.

## Update

When new features or upstream skills are added, pull the changes and re-run the installer to sync and re-generate your `SKILL.md` files.

```bash
cd ~/.local/share/Sylveste
git pull
git submodule update --init --recursive
bash scripts/install-gemini-interverse.sh install
```

## Uninstall

If you ever wish to remove the Gemini skills globally:

```bash
cd ~/.local/share/Sylveste
bash scripts/install-gemini-interverse.sh uninstall
```

Then you may safely remove the `Sylveste` clone directory.

## Working with Clavain in Gemini CLI

Gemini CLI supports Sylveste slash commands through custom `.toml` command files. Namespaced paths under `.gemini/commands/` map directly to slash commands:

- `.gemini/commands/clavain/route.toml` → `/clavain:route`
- `.gemini/commands/interflux/flux-drive.toml` → `/interflux:flux-drive`
- `.gemini/commands/interpath/roadmap.toml` → `/interpath:roadmap`

To use the installed skills directly, you can also use the built-in `activate_skill` tool or let Gemini autonomously activate them depending on the task context.
