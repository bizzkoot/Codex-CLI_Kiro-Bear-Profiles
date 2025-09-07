# Codex CLI Alias Installer

A production-ready Bash installer for setting up **Kiro** and **Bear** agent playbooks with OpenAI Codex CLI.

## Features

- 🚀 **Production Ready** — versioned from v1.0.0
- 🖥️ **macOS Compatible** — works with system Bash 3.2 (no `mapfile` dependency)
- 🔢 **Flexible Tier Selection** — choose by number (1–4) or name (min/low/mid/high)
- 🤝 **Interactive Flow** — clear prompts for fresh setup, tier model IDs, and playbook overwrites
- 📂 **Path Handling** — accepts quoted paths, spaces, and `~` home expansion
- ✍️ **Embedded Playbooks** — `kiro.md` and `bear.md` included inside the script, no external fetch required
- 🛡️ **Safe by Default** — asks before overwriting files, requires `--force` in non-interactive mode

## Installation

Download the script and run with Bash:

```bash
bash install_codex_aliases-1.0.0.sh
```

## Usage (Interactive)

1. Choose which tiers to install (e.g., `2,3` → low + mid).
2. Decide if you want a **fresh global setup** (profiles + shell functions).
3. Provide model IDs for chosen tiers (defaults prefilled).
4. Confirm whether to overwrite existing playbooks (`kiro.md` and `bear.md`) if present.
5. Reload your shell config to activate aliases:

```bash
source ~/.zshrc   # or ~/.bashrc
```

## Usage (Non-Interactive)

You can also run with flags for automation:

```bash
# Fresh setup with defaults
install_codex_aliases-1.0.0.sh --fresh

# Install playbooks into a repo (overwrite with --force)
install_codex_aliases-1.0.0.sh --repo /path/to/repo --force
```

## Aliases Installed

- `/kiro`, `/bear` → mid tier (default)
- `/kiro-min`, `/bear-min`
- `/kiro-low`, `/bear-low`
- `/kiro-mid`, `/bear-mid`
- `/kiro-high`, `/bear-high`

Check them after install:
```bash
/codex-aliases
```

## Requirements

- Bash 3.2+ (default on macOS is supported)
- [OpenAI Codex CLI](https://github.com/openai/codex-cli) installed and available in `PATH`

## License

MIT License. Use at your own risk.

