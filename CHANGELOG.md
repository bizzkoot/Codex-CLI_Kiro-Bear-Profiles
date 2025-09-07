# Changelog

All notable changes to this project will be documented in this file.

## [1.0.3] - 2025-09-07
### Fixed
- Corrected `prompt_files` entries written to `~/.codex/config.toml` profiles.  
  v1.0.2 mistakenly wrote literal placeholders like `codex/${name%%_*}.md`, causing Codex to miss repo/global playbooks.  
  v1.0.3 now resolves the role base (`kiro`/`bear`) explicitly and writes concrete paths:  
  `prompt_files = ["codex/<role>.md", "~/.codex/playbooks/<role>.md"]` (repo-first, global fallback).

### Changed
- Bumped release to `v1.0.3`; installer renamed to `install_codex_aliases-1.0.3.sh` and internal `VERSION=1.0.3`.
- Updated alias block markers in shell RC to `# BEGIN/END CODEX ALIASES v1.0.3` and aligned `--check`/`--uninstall` logic.

### Documentation
- Updated README badge and all install commands to reference `install_codex_aliases-1.0.3.sh`.
- Clarified repo-first/global-fallback behavior for playbooks in usage text.

## [1.0.2] - 2025-09-07
### Changed
- Bumped release to `v1.0.2`; installer renamed to `install_codex_aliases-1.0.2.sh` and internal `VERSION=1.0.2`.
- Simplified Kiro/Bear thinking flows: concise preview → approve → write loops for Kiro; Bear focuses on incremental execution with patch-ready diffs.

### Documentation
- Updated README badge and all install commands to reference `install_codex_aliases-1.0.2.sh`.

## [1.0.1] - 2025-09-07
### Changed
- Bumped release to `v1.0.1`; installer script renamed to `install_codex_aliases-1.0.1.sh` and internal `VERSION=1.0.1`.
- Updated README badge and all install commands to use `install_codex_aliases-1.0.1.sh`.
- Corrected tier semantics: tiers now explicitly map to reasoning effort levels (`minimal`, `low`, `medium`, `high`) for a single model (`gpt-5`).

### Fixed
- Replaced incorrect model IDs (`gpt-5-low`, `gpt-5-medium`, etc.) with the proper `model_reasoning_effort` usage.

### Documentation
- Updated environment override examples to use `CODEX_MODEL` and `CODEX_REASONING_*` variables (replacing `CODEX_*_MODEL`).
- Updated repository links to: https://github.com/bizzkoot/Codex-CLI_Kiro-Bear-Profiles

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
