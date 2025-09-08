# Changelog

All notable changes to this project will be documented in this file.

## [1.0.4] - 2025-09-08
### Changed
- Bumped release to `v1.0.4`; installer renamed to `install_codex_aliases-1.0.4.sh` and internal `VERSION=1.0.4`.
- Updated alias block markers in shell RC to `# BEGIN/END CODEX ALIASES v1.0.4` (dynamic via `$VERSION`).

### Added
- **Role-based enforcement** in profiles:
  - **Kiro**: `approval_policy="untrusted"`, `sandbox_mode="read-only"`, `model_verbosity="low"`.
  - **Bear**: `approval_policy="on-request"`, `sandbox_mode="workspace-write"`, `model_verbosity="medium"`.
- Support for nested TOML sub-tables: `[profiles.bear_<tier>.sandbox_workspace_write]` with `writable_roots` and `network_access = false` (if `CODEX_BEAR_WRITABLE_ROOTS` is set).
- Interactive/global option to set **file_opener** (`vscode`, `vscode-insiders`, `windsurf`, `cursor`, `none`).  
  Written as a top-level `file_opener` key in `~/.codex/config.toml`.
- Explicit **handoff guidance**: Kiro playbook now prints  
  `SWITCH TO BEAR: /bear-mid "<ABSOLUTE_PATH_TO_tasks.md>"`  
  after writing `tasks.md`.

### Fixed
- **Regex escaping bug**: corrected profile removal logic in `add_or_update_profile()` to properly escape dots (`.`) in section names and to match headers exactly (`^\[profiles.<name>\]$`).
- **Health check race condition**: sandbox verification and model availability probes now run *after* profiles/aliases/playbooks are written.
- **Argument parsing typo**: removed stray `DO_CHECKCAL=0` in `--check` branch.
- **Dead code**: `verify_profile_creation()` is now actively used after profile writes, warning if a profile fails to appear in `config.toml`.

### Improved
- **Health check clarity**: `verify_sandbox_config()` now differentiates between:
  - Kiro profiles correctly configured for read-only.
  - Bear profiles correctly configured for workspace-write.
  - Bear profiles incorrectly stuck in read-only, with remedial `codex --profile <p> --sandbox workspace-write` advice.
- More consistent and descriptive success/error messages across profile creation and sandbox verification.
- Interactive flow improved with clearer separation of `NEEDS_FRESH_INSTALL` and `NEEDS_REPO_INSTALL`.

### Documentation
- Updated usage text to show new file_opener option and Bear handoff convention.
- Clarified behavior of Kiro (STRICT planning, never edits code files) vs. Bear (executor with optional APPLY? gating).

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
