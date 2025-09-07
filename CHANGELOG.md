# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2025-09-07
### Added
- First production-ready release of `install_codex_aliases.sh`.
- Embedded **kiro.md** and **bear.md** playbooks directly in the script (no placeholders).
- macOS compatibility: removed `mapfile` dependency (works with Bash 3.2).
- Tier selection now accepts both numeric (`1,2,3,4`) and names (`min,low,mid,high`).
- Interactive flow:
  - Asks for **fresh setup** before prompting for model IDs.
  - Only prompts for model IDs relevant to the chosen tiers (+ always `mid`).
- Path normalization:
  - Handles quoted paths with spaces.
  - Expands `~` to `$HOME`.
- Interactive overwrite confirmation for existing playbooks (`kiro.md`, `bear.md`).
- Clear success/error messaging with ✅/⚠️/❌ indicators.

