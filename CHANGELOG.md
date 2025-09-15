# Changelog

All notable changes to this project will be documented in this file.

## [2.0.5] - 2025-09-16

### Added
- **Interactive Model Selection**: The installer now prompts users to choose between `gpt-5` (default) and the new `gpt-5-codex` model.
- **Conditional Reasoning Tiers**: The available reasoning tiers are now conditional on the selected model. `gpt-5-codex` is limited to `low`, `mid`, and `high` tiers, while `gpt-5` retains all four (`min`, `low`, `mid`, `high`).

### Changed
- The interactive installation flow has been updated to present the model selection before the tier selection to support conditional choices.
- The non-interactive tier parsing logic (`--tiers` flag) is now model-aware and will validate tiers against the selected model (`gpt-5` or `gpt-5-codex`).

### Technical
- **Version**: Bumped to `v2.0.5`.

## [2.0.4] - 2025-09-15

### Added
- **Web Search Capability**: Kiro now has web search enabled by default to enhance planning with external context. Bear's web search is opt-in and can be enabled per-call via the `CODEX_WEB_SEARCH=1` environment variable.
- **Runtime File Opener Override**: The file opener can now be dynamically set at runtime by the `CODEX_FILE_OPENER` environment variable, which overrides the default value set during installation.

### Changed
- **Default Verbosity Levels**: Adjusted default verbosity to better suit agent roles. Kiro now defaults to `low` for more concise planning output, while Bear defaults to `medium` for balanced implementation detail.

### Fixed
- **Exit Code Propagation**: Shell functions for Kiro and Bear now correctly propagate non-zero exit codes from the Codex CLI, allowing for more reliable scripting and error detection.

### Technical
- **Refactored Function Generation**: The script's internal logic for generating the shell configuration has been streamlined for improved clarity and maintenance.
- **Version**: Bumped to `v2.0.4`.

## [2.0.3] - 2025-09-12

### Fixed
- **Critical Bear profile bug**: Bear profiles were generating empty content due to missing function calls in the generation logic. All Bear functions (`bear-min`, `bear-low`, `bear-mid`) now properly embed their profile instructions instead of empty heredoc blocks.
- **Variable expansion in Bear profiles**: Corrected `generate_bear_profile()` to use unquoted heredoc (`<<EOF` instead of `<<'EOF'`) allowing proper substitution of `${tier}`, `${CODEX_MODEL}`, and `${reasoning}` variables.

### Changed
- **Code cleanup**: Streamlined redundant comments and consolidated similar error messages, reducing script size by ~20 lines while maintaining full functionality.
- **Version banner**: Added "FIXED" notice in interactive mode to highlight the Bear profile repair.

### Added
- **Interactive/global file opener (embedded only)**: The embedded installer now supports selecting a default `file_opener` without touching `~/.codex/config.toml`.
  - Supported values: `vscode` (default), `vscode-insiders`, `windsurf`, `cursor`, `none`.
  - Selection methods:
    - Interactive: prompted during installation with the current value as default.
    - CLI: `--file-opener <opener>`.
    - Env: `CODEX_FILE_OPENER=<opener>`.
  - Propagation: passed to Codex via `--config file_opener=<opener>` alongside `model_reasoning_effort` in both Kiro and Bear functions.
  - Visibility: shown in the generated block header, `codex-status`, and the Installation Summary.

### Technical
- **Version**: Bumped to `v2.0.3`.
- **Backward compatibility**: Existing v2.0.2 installations should reinstall to get working Bear functions.

### Migration from v2.0.2
Users with v2.0.2 installations should run:
```bash
bash codex_interactive_embedded.sh --auto --mode overwrite
source ~/.zshrc  # or ~/.bashrc
bear-test  # Should now work correctly
```

## [2.0.2] - 2025-09-11

### Added
- **Cross-platform editing**: Introduced `safe_sed_inplace` helper for atomic, portable in-place edits (avoids BSD/GNU sed differences).
- **Auto-mode validation**: `--auto` now checks for Codex CLI presence and fails fast with a clear error if missing.

### Changed
- **Bash version guidance**: Clearer version check messaging and platform-specific upgrade instructions; includes Apple Silicon/Intel invocation hints.
- **RC file detection**: `detect_shell_rc()` now falls back to `~/.bash_profile` when `~/.bashrc` is absent (improves default bash setups on macOS/Linux).
- **Bear profile flow**: Refined input resolution and missing-tasks bootstrap (creates concise stub, prints a compact plan, and uses consistent decision prompts). Excludes archived specs from discovery and standardizes archive directories to `YYYY-MM-DD_{slug}`.
- **Prompting style**: Removed explicit “No Chain-of-Thought” directive; defers to Codex CLI to determine reasoning style.
- **Polish**: Minor copy edits to banners and help output.

### Fixed
- **Slug utility**: `feature_slugify()` now reliably produces kebab-case via `tr` + `sed -E`, correctly trimming leading/trailing dashes.
- **Uninstall portability**: Replaced `sed -i` usage with an atomic temp-file approach (`safe_sed_inplace`) for consistent uninstall behavior across environments.

### Technical
- **Version**: Bumped to `v2.0.2`.

## [2.0.1] - 2025-09-10

### Enhanced
- **Token-optimized profiles**: Reduced profile size by ~40% while maintaining full functionality
- **Unicode character fixes**: Corrected all mangled Unicode characters (emojis, box drawing)
- **Numbered file structure**: Restored numbered file workflow (`00_requirements.md`, `10_design.md`, `20_tasks.md`)
- **Feature slugify utility**: Added missing `feature_slugify()` function for kebab-case conversion
- **Version flag**: Added `--version` command line option
- **Profile improvements**: Enhanced clarity and added "Numbered Files Rationale" section

### Added
- **Context awareness**: Bear now explicitly reads all three planning files (00_, 10_, 20_) for full context
- **Archive flow documentation**: Detailed archive workflow with date-stamped folders (`/specs/Done/{feature-slug}/{YYYY-MM-DD}/`)
- **Input resolution**: Bear supports multiple input formats (absolute path, shorthand slug, auto-detect)
- **EARS-style acceptance criteria**: Lightweight traceability without overwhelming complexity
- **Merge capability**: Incremental updates to existing planning files

### Fixed
- **Profile consistency**: Unified handoff mechanism using numbered file paths
- **Bear profile**: Enhanced to mention reading requirements, design, and tasks for context
- **Installation robustness**: Better tier management and error handling
- **Unicode display**: Proper emoji and symbol rendering in terminals

### Technical
- **Profile structure**: Maintains original v2.0.0 workflow with numbered file enhancements
- **Token efficiency**: Kiro ~280 tokens, Bear ~200 tokens (vs ~600+ in verbose versions)
- **Backward compatibility**: Existing installations upgrade smoothly

## [2.0.0] - 2025-09-09

### Migration Notes (from v1.0.x to v2.0.0)
If you previously installed using `install_codex_aliases.sh` (or its versioned variants like `install_codex_aliases-1.0.4.sh`), you should uninstall the old aliases and functions before switching to the new unified installer.

You can safely remove them with the following command snippet (copy & paste into your shell):

```bash
# Uninstall previous Codex aliases/profiles (v1.0.x) – NO BACKUP
set -euo pipefail

# 1) Remove alias/function blocks from common shell RC files
for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
  [ -f "$rc" ] || continue
  # Old aliases block (v1.0.x)
  if grep -q "^# BEGIN CODEX ALIASES" "$rc"; then
    awk '
      /^# BEGIN CODEX ALIASES/ {skip=1}
      skip==0 {print}
      /^# END CODEX ALIASES/ {skip=0}
    ' "$rc" > "${rc}.tmp" && mv "${rc}.tmp" "$rc"
    echo "Removed CODEX ALIASES block from $rc"
  fi
  # Embedded functions block (newer installers)
  if grep -q "^# BEGIN EMBEDDED CODEX FUNCTIONS" "$rc"; then
    sed -i.tmp '/# BEGIN EMBEDDED CODEX FUNCTIONS/,/# END EMBEDDED CODEX FUNCTIONS/d' "$rc"
    rm -f "${rc}.tmp"
    echo "Removed EMBEDDED CODEX FUNCTIONS block from $rc"
  fi
done

# 2) Remove global playbooks (if present)
rm -f "$HOME/.codex/playbooks/kiro.md" "$HOME/.codex/playbooks/bear.md" || true

# 3) Remove kiro_*/bear_* profiles from ~/.codex/config.toml
cfg="$HOME/.codex/config.toml"
if [ -f "$cfg" ]; then
  awk '
    BEGIN{skip=0}
    # Start skipping Kiro/Bear tiered profile sections and subtables
    /^\[profiles\.(kiro|bear)_(min|low|mid|high)\]$/ {skip=1; next}
    /^\[profiles\.(kiro|bear)_(min|low|mid|high)\./ {skip=1; next}
    # On any new TOML table header, stop skipping
    /^\[/ { if (skip==1) { skip=0 } }
    skip==0 { print }
  ' "$cfg" > "${cfg}.tmp" && mv "${cfg}.tmp" "$cfg"
  echo "Pruned kiro_*/bear_* profiles from $cfg"
fi

# 4) Reload your shell to apply changes
if [ -n "${ZSH_VERSION:-}" ]; then source "$HOME/.zshrc"; fi
if [ -n "${BASH_VERSION:-}" ]; then source "$HOME/.bashrc" 2>/dev/null || true; fi
```

After cleanup, install using:

```bash
bash codex_interactive_embedded.sh
```

### Changed
- Consolidated installer script under a single name: `codex_interactive_embedded.sh`. Removed version suffixes in filenames to simplify README linking and user management.
- Direct embedding into `~/.zshrc` or `~/.bashrc`, replacing the earlier approach of managing profiles via `--profile` flag.

### Notes
- Earlier v1.0.x attempts relied on `--profile` injection, which proved unreliable. This has been replaced by a direct-write strategy into the user's shell RC file for consistent function availability.
- The script now provides intelligent reinstall/uninstall flows:
  - Interactive overwrite/skip/delete choices on reinstall.
  - Backup prompt with configurable directory on uninstall.
  - Robust parsing of tier selections to eliminate "unknown tier" warnings.
- Bash version check added: requires Bash >= 4.0. If older, users are given upgrade instructions (Homebrew on macOS, package manager on Linux).

## [1.0.5] - 2025-09-09
### Fixed
- Alias functions now forward arguments reliably by preventing early expansion of "$@" when writing the alias block.
- Uninstall removes alias block regardless of versioned markers (version-agnostic BEGIN/END matching).
- Profile overwrite on macOS: replace awk state variable `in` with `inside` to avoid BSD awk reserved keyword error.

### Changed
- Use unversioned alias block markers and add a separate version comment line for traceability.
- Unify Kiro/Bear playbooks via shared templates; repo and global playbooks now have identical content generated from a single source.

### Documentation
- README: update badges, simplify install commands to `install_codex_aliases.sh`, add uninstall section and advanced notes.
- .gitignore: ignore `scripts/` (tools) and keep repository noise low.

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