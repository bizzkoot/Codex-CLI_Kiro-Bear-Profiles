#!/usr/bin/env bash
set -euo pipefail

# Ensure running under bash (not plain sh/zsh)
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Please run with bash: bash $0" >&2
  exit 1
fi

VERSION="1.0.5"
SCRIPT_NAME="install_codex_aliases-${VERSION}.sh"

# ───────────────────────── helpers ─────────────────────────
ce(){ printf "%s\n" "$*" >&2; }
info(){ ce "👉 $*"; }
ok(){ ce "✅ $*"; }
warn(){ ce "⚠️  $*"; }
err(){ ce "❌ $*"; }
sep(){ ce "────────────────────────────────────────────────────"; }

usage() {
  # Use current VERSION in banner (no hardcoded version)
  cat <<EOF
install_codex_aliases.sh  v${VERSION}  (Codex CLI native, gpt-5 with tiered reasoning)

Highlights:
  • Kiro STRICT: read-only, writes only requirements.md, design.md, tasks.md with DECIDE → APPROVE | REVISE | CANCEL.
  • Bear APPLY? gate (optional), allows AUTO to continue ungated.
  • Handoff line after tasks.md write:
      SWITCH TO BEAR: /bear-mid "<ABSOLUTE_PATH_TO_tasks.md>"
  • Per-profile policies:
      Kiro: approval_policy="untrusted", sandbox_mode="read-only", model_verbosity="low"
      Bear: approval_policy="on-request", sandbox_mode="workspace-write", model_verbosity="medium"
    + Correct nested sub-table: [profiles.<name>.sandbox_workspace_write] if CODEX_BEAR_WRITABLE_ROOTS is set.
  • Global file_opener selection and write (does NOT modify reasoning):
      Allowed: vscode (default) · vscode-insiders · windsurf · cursor · none
  • Dynamic BEGIN/END markers tied to $VERSION.
  • Health checks: model availability probe & sandbox verification (post-creation).

Usage (non-interactive):
  install_codex_aliases.sh --fresh [--force] [--file-opener OPENER]
  install_codex_aliases.sh --repo PATH [--force]
  install_codex_aliases.sh --fresh --repo PATH [--force] [--file-opener OPENER]
  install_codex_aliases.sh --check
  install_codex_aliases.sh --uninstall
  install_codex_aliases.sh -h | --help

Environment overrides (non-interactive only):
  CODEX_MODEL=gpt-5
  CODEX_REASONING_MIN=minimal
  CODEX_REASONING_LOW=low
  CODEX_REASONING_MID=medium
  CODEX_REASONING_HIGH=high
  CODEX_TIERS=min,low,mid,high   # which tiers to install (subset, comma-separated)
  CODEX_FILE_OPENER=vscode|vscode-insiders|windsurf|cursor|none
  CODEX_BEAR_WRITABLE_ROOTS=/abs/path1,/abs/path2   # optional Bear nested table
  CODEX_FALLBACK_MODEL=o4-mini                      # optional probe hint (no auto flip)
EOF
}

# ───────────────────────── defaults ─────────────────────────
: "${CODEX_MODEL:="gpt-5"}"
REASON_MIN="${CODEX_REASONING_MIN:-minimal}"
REASON_LOW="${CODEX_REASONING_LOW:-low}"
REASON_MID="${CODEX_REASONING_MID:-medium}"
REASON_HIGH="${CODEX_REASONING_HIGH:-high}"
TIERS_CSV="${CODEX_TIERS:-}"

# Global install locations
: "${CODEX_GLOBAL_DIR:="$HOME/.codex"}"
: "${CODEX_PLAYBOOK_DIR:="$CODEX_GLOBAL_DIR/playbooks"}"
KIRO_PB_GLOBAL="$CODEX_PLAYBOOK_DIR/kiro.md"
BEAR_PB_GLOBAL="$CODEX_PLAYBOOK_DIR/bear.md"

# file_opener (global, optional; default vscode)
FILE_OPENER="${CODEX_FILE_OPENER:-vscode}"

_abs_path() {
  case "$1" in
    /*) printf "%s\n" "$1" ;;
    *) printf "%s\n" "$(cd "$(pwd)" >/dev/null 2>&1 && cd "$(dirname "$1")" >/dev/null 2>&1 && pwd)/$(basename "$1")" ;;
  esac
}
normalize_path(){ _abs_path "$1"; }

ask_yes_no() {
  local prompt="${1:-Continue?}"; local def="${2:-Y}"; local ans
  read -r -p "${prompt} [${def}/n]: " ans || true
  ans="${ans:-$def}"
  case "$ans" in
    Y|y|yes|YES) printf "Y" ;;
    *) printf "N" ;;
  esac
}

# ───────────────────────── args ─────────────────────────
FORCE=0
DO_CHECK=0
DO_UNINSTALL=0
DO_FRESH=0
REPO_PATH_INPUT=""
CLI_FILE_OPENER=""
INTERACTIVE=0
if [[ -t 0 && -t 1 ]]; then INTERACTIVE=1; fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fresh) DO_FRESH=1; shift ;;
    --repo) REPO_PATH_INPUT="${2:-}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --check) DO_CHECK=1; shift ;;
    --uninstall) DO_UNINSTALL=1; shift ;;
    --file-opener) CLI_FILE_OPENER="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown arg: $1"; usage; exit 2 ;;
  esac
done

if [[ -n "${CLI_FILE_OPENER:-}" ]]; then FILE_OPENER="$CLI_FILE_OPENER"; fi
validate_file_opener() {
  case "$1" in
    vscode|vscode-insiders|windsurf|cursor|none) return 0 ;;
    *) return 1 ;;
  esac
}
if ! validate_file_opener "$FILE_OPENER"; then
  warn "Invalid file_opener '${FILE_OPENER}', defaulting to 'vscode'"
  FILE_OPENER="vscode"
fi

# ───────────────────────── detect shell rc ─────────────────────────
detect_shell_rc() {
  local rcfile=""
  if [[ -n "${ZSH_VERSION-}" ]] || [[ "${SHELL-}" == *"/zsh" ]]; then
    rcfile="${HOME}/.zshrc"
  elif [[ -n "${BASH_VERSION-}" ]] || [[ "${SHELL-}" == *"/bash" ]]; then
    rcfile="${HOME}/.bashrc"
  else
    rcfile="${HOME}/.zshrc"
  fi
  printf "%s" "$rcfile"
}

# ───────────────────────── require codex ─────────────────────────
check_codex() {
  if ! command -v codex >/dev/null 2>&1; then
    warn "Codex CLI not found in PATH."
    ce "Install it first (examples):"
    ce "  npm i -g @openai/codex   # or"
    ce "  brew install codex        # if available on your platform"
    exit 1
  fi
}

# ───────────────────────── profiles (global config) ─────────────────────────
ensure_profiles_for_tier() {
  local tier="$1"; shift
  local cfg="$1"; shift
  local changed=0
  local effort="medium"
  case "$tier" in
    min) effort="$REASON_MIN" ;;
    low) effort="$REASON_LOW" ;;
    mid) effort="$REASON_MID" ;;
    high) effort="$REASON_HIGH" ;;
  esac

  add_or_update_profile() {
    local name="$1" ; shift
    local role_base="${name%%_*}"  # kiro or bear
    local repo_prompt="codex/${role_base}.md"
    local global_prompt="${CODEX_PLAYBOOK_DIR}/${role_base}.md"

    # Role-specific enforcement
    local approval="on-request"
    local sandbox="workspace-write"
    local verbosity="medium"
    if [[ "$role_base" == "kiro" ]]; then
      approval="untrusted"
      sandbox="read-only"
      verbosity="low"
    fi

    # Remove existing profile and any sub-tables safely (regex-escaped, exact match on main header)
    if grep -q "^\[profiles\.${name}\]" "$cfg"; then
      if [[ "$FORCE" -eq 1 ]] || ([[ $INTERACTIVE -eq 1 ]] && [[ "$(ask_yes_no "Profile [${name}] exists in $cfg. Overwrite?" "N")" == "Y" ]]); then
        info "Removing existing profile [${name}] to update"
        local escaped_name
        escaped_name="$(printf "%s" "${name}" | sed 's/\./\\./g')"
        awk -v section="profiles.${escaped_name}" '
          BEGIN { inside=0 }
          $0 ~ "^\[" section "\]$" { inside=1; next }
          $0 ~ "^\[" section "\." { inside=1; next }
          /^\[/ { inside=0 }
          !inside { print }
        ' "$cfg" > "${cfg}.tmp" && mv "${cfg}.tmp" "$cfg"
      else
        info "Keeping existing profile [${name}]"
        return
      fi
    fi

    info "Adding/Updating profile [${name}]"
    cat >>"$cfg" <<EOF

[profiles.${name}]
prompt_files = ["${repo_prompt}", "${global_prompt}"]
model = "${CODEX_MODEL}"
model_reasoning_effort = "${effort}"
approval_policy = "${approval}"
sandbox_mode = "${sandbox}"
model_verbosity = "${verbosity}"
EOF

    # Nested workspace write table for Bear, if configured
    if [[ "$role_base" == "bear" && -n "${CODEX_BEAR_WRITABLE_ROOTS:-}" ]]; then
      IFS=',' read -r -a roots <<< "${CODEX_BEAR_WRITABLE_ROOTS}"
      items=""
      for r in "${roots[@]}"; do
        r="$(printf "%s" "$r" | xargs)"
        [[ -n "$r" ]] || continue
        items="${items}\"$r\","
      done
      items="${items%,}"
      if [[ -n "$items" ]]; then
        cat >>"$cfg" <<EOF
[profiles.${name}.sandbox_workspace_write]
writable_roots = [${items}]
network_access = false
EOF
      fi
    fi

    ok "Wrote [profiles.${name}]"
    if ! verify_profile_creation "${name}"; then
      warn "Profile ${name} may not have been created properly"
      return 1
    fi
    changed=1
  }

  add_or_update_profile "kiro_${tier}"
  add_or_update_profile "bear_${tier}"

  return $changed
}

ensure_profiles() {
  local cfg="${HOME}/.codex/config.toml"
  local cfgdir; cfgdir="$(dirname "$cfg")"
  mkdir -p "$cfgdir"

  if [[ -f "$cfg" ]]; then
    info "Found $cfg"
    cp "$cfg" "${cfg}.bak.$(date +%Y%m%d-%H%M%S)"
  else
    info "Creating $cfg"
    : > "$cfg"
  fi

  local changed_any=0

  # Always create 'mid' base aliases (/kiro -> kiro_mid, /bear -> bear_mid)
  ensure_profiles_for_tier "mid" "$cfg" && changed_any=1

  if [[ " ${SELECTED_TIERS[*]} " == *" min "* ]]; then
    ensure_profiles_for_tier "min" "$cfg" && changed_any=1
  fi
  if [[ " ${SELECTED_TIERS[*]} " == *" low "* ]]; then
    ensure_profiles_for_tier "low" "$cfg" && changed_any=1
  fi
  if [[ " ${SELECTED_TIERS[*]} " == *" high "* ]]; then
    ensure_profiles_for_tier "high" "$cfg" && changed_any=1
  fi

  if [[ $changed_any -eq 0 ]]; then
    info "No changes to $cfg (profiles already configured)"
  fi
}

# Write/replace global file_opener only (do NOT touch reasoning settings)
write_global_file_opener() {
  local cfg="${HOME}/.codex/config.toml"
  [[ -f "$cfg" ]] || { warn "No $cfg present yet (creating)"; : > "$cfg"; }

  # Remove existing top-level file_opener if present
  if grep -q '^file_opener\s*=' "$cfg"; then
    awk '!/^file_opener\s*=/' "$cfg" > "${cfg}.tmp" && mv "${cfg}.tmp" "$cfg"
  fi

  # Append at end
  echo "file_opener = \"${FILE_OPENER}\"" >> "$cfg"
  ok "Set global file_opener = \"${FILE_OPENER}\" in $cfg"
}

codex_cli_capabilities() {
  # Echoes two flags: HAS_CHAT HAS_DRY_RUN (1/0)
  local has_chat=0 has_dry_run=0
  if codex chat --help >/dev/null 2>&1; then
    has_chat=1
    if codex chat --help 2>&1 | grep -q -- "--dry-run"; then
      has_dry_run=1
    fi
  fi
  echo "$has_chat $has_dry_run"
}

# --- Optional health checks ---
verify_sandbox_config() {
  local p="$1"
  info "Verifying profile reachable (dry-run): $p"
  if ! command -v codex >/dev/null 2>&1; then
    warn "Codex not available for verification"
    return 1
  fi
  read -r HAS_CHAT HAS_DRY_RUN < <(codex_cli_capabilities)
  if [[ "$HAS_CHAT" -eq 1 && "$HAS_DRY_RUN" -eq 1 ]]; then
    if codex chat --profile "$p" --dry-run >/dev/null 2>&1; then
      ok "Profile $p is reachable (dry-run succeeded)"
    else
      warn "Dry-run failed for profile $p (model or profile config may be invalid)"
    fi
  else
    info "Skipping profile dry-run: this Codex CLI does not support 'chat --dry-run'"
  fi
}

check_model_availability() {
  local primary_model="${1:-gpt-5}"
  local fallback_model="${CODEX_FALLBACK_MODEL:-o4-mini}"
  read -r HAS_CHAT HAS_DRY_RUN < <(codex_cli_capabilities)
  if [[ "$HAS_CHAT" -eq 1 && "$HAS_DRY_RUN" -eq 1 ]]; then
    if codex chat --model "$primary_model" --dry-run >/dev/null 2>&1; then
      ok "Model '$primary_model' appears available"
    else
      warn "Model '$primary_model' may not be available"
      if codex chat --model "$fallback_model" --dry-run >/dev/null 2>&1; then
        info "Fallback model '$fallback_model' appears available"
        ce "   Consider setting CODEX_MODEL='$fallback_model' and rerunning"
      else
        warn "Neither primary nor fallback model appears available"
      fi
    fi
  else
    info "Skipping model probe: this Codex CLI does not support 'chat --dry-run'"
  fi
}

verify_profile_creation() {
  local name="$1"
  local cfg="${HOME}/.codex/config.toml"
  if grep -q "^\[profiles\.${name}\]" "$cfg" 2>/dev/null; then
    ok "Profile [${name}] created successfully"
    return 0
  else
    err "Failed to create profile [${name}]"
    warn "This may indicate a TOML syntax error or permission issue."
    return 1
  fi
}

# ───────────────────────── shell functions (BEGIN/END block) ─────────────────────────
install_shell_block() {
  local rcfile; rcfile="$(detect_shell_rc)"
  info "Using shell rc: $rcfile"
  [[ -f "$rcfile" ]] || : > "$rcfile"
  cp "$rcfile" "${rcfile}.bak.$(date +%Y%m%d-%H%M%S)"

  local begin_marker="# BEGIN CODEX ALIASES"
  local end_marker="# END CODEX ALIASES"

  # Remove any existing alias blocks from any version (idempotent)
  if grep -q "^# BEGIN CODEX ALIASES" "$rcfile" 2>/dev/null; then
    awk '
      /^# BEGIN CODEX ALIASES/ {skip=1}
      skip==0 {print}
      /^# END CODEX ALIASES/ {skip=0}
    ' "$rcfile" > "${rcfile}.tmp" && mv "${rcfile}.tmp" "$rcfile"
  fi

  cat >> "$rcfile" <<EOF
$begin_marker
# CODEX ALIASES version: ${VERSION}
# Aliases call Codex profiles; profiles define repo-first prompt_files with a global fallback.

alias /codex-aliases='alias | grep -E "^/(kiro|bear)" | sort'

# Kiro (planning & artifacts)
/kiro()       { codex --profile kiro_mid  "\$@"; }
/kiro-min()   { codex --profile kiro_min  "\$@"; }
/kiro-low()   { codex --profile kiro_low  "\$@"; }
/kiro-mid()   { codex --profile kiro_mid  "\$@"; }
/kiro-high()  { codex --profile kiro_high "\$@"; }

# Bear (implementation & diffs)
/bear()       { codex --profile bear_mid  "\$@"; }
/bear-min()   { codex --profile bear_min  "\$@"; }
/bear-low()   { codex --profile bear_low  "\$@"; }
/bear-mid()   { codex --profile bear_mid  "\$@"; }
/bear-high()  { codex --profile bear_high "\$@"; }
$end_marker
EOF

  ok "Functions installed in $rcfile (between BEGIN/END markers)"
  ce "To load them now, run: source \"$rcfile\""
}

# ───────────────────────── playbooks (shared templates + writers) ─────────────────────────
render_kiro_template() {
  cat <<'KIRO_EOF'
# Kiro (Codex CLI) — STRICT Planning & Artifacts (No Chain-of-Thought)

Startup
🛑 MUST: The first line of your FIRST assistant message is exactly:
  Profile /kiro loaded
  - Print it on its own line, with no leading/trailing spaces.
  - Do NOT include any text, emojis, markdown, or code fences before it.
  - Immediately after, continue with your normal response.
  - If you fail to print it first, immediately correct by printing that exact line on the next line, then proceed.

**Runtime:** Codex CLI profile `kiro_*` (model: gpt-5, reasoning: tiered).
**Goal:** Maintain `requirements.md`, `design.md`, `tasks.md` via preview → APPROVE/REVISE → write loops.
**Resumable:** On re-run, read existing files and propose concise diffs.

## HARD RULE — NEVER edit code files
Kiro must not create/modify/delete code files. It only writes these artifacts after APPROVE:
- `requirements.md`
- `design.md`
- `tasks.md`

If the user asks to modify code, reply with a single line:
SWITCH TO BEAR: /bear-mid "<ABSOLUTE_PATH_TO_tasks.md>"

## Behavior
- Be concise. Do not print chain-of-thought. Ask ≤2 clarifying questions only if essential.
- Prefer EARS-style requirements; keep traceability light.
- When updating, show a minimal diff before writing.
- Always re-read existing markdowns and update incrementally.

## Flow
1) Requirements PREVIEW (bulleted): scope, constraints, acceptance criteria (IDs).
   Wait for APPROVE or REVISE. If APPROVE → write `requirements.md`.
2) Design PREVIEW (bulleted): components, integration points, risks/mitigations.
   Wait for APPROVE or REVISE. If APPROVE → write `design.md`.
3) Tasks PREVIEW: numbered, small, testable tasks, reference AC IDs.
   Wait for APPROVE or REVISE. If APPROVE → write/merge `tasks.md`.

After writing/merging `tasks.md`, output a ready-to-paste handoff line (using the absolute path):
SWITCH TO BEAR: /bear-mid "<ABSOLUTE_PATH_TO_tasks.md>"

## Decision Prompt
At the end of each PREVIEW, include exactly:
DECIDE → Reply exactly with one of:
- APPROVE
- REVISE: <your changes or constraints>
- CANCEL
KIRO_EOF
}

render_bear_template() {
  cat <<'BEAR_EOF'
# Bear (Codex CLI) — Lean Executor (No Chain-of-Thought)

Startup
🛑 MUST: The first line of your FIRST assistant message is exactly:
  Profile /bear loaded
  - Print it on its own line, with no leading/trailing spaces.
  - Do NOT include any text, emojis, markdown, or code fences before it.
  - Immediately after, continue with your normal response.
  - If you fail to print it first, immediately correct by printing that exact line on the next line, then proceed.

**Runtime:** Codex CLI profile `bear_*` (model: gpt-5, reasoning: tiered).
**Purpose:** Implement tasks from `tasks.md` (or a provided task) with small patches and quick validation.

## Behavior
- Be concise. Do not print chain-of-thought.
- Start with a micro-plan (3–6 bullets). Reference `tasks.md` item IDs.
- Produce patch-ready diffs (unified) or exact file blocks; favor small, testable increments.
- Run/validate when appropriate; summarize results; propose the next step.

## Optional Confirmation (for risky/large changes)
Show the diff first, then wait:
APPLY? → Reply exactly with:
- APPLY
- REVISE: <what to change>
- CANCEL

If the user replies AUTO once in this run, proceed without further confirmations.
BEAR_EOF
}

# Writers using the shared templates
write_playbooks_global() {
  mkdir -p "$CODEX_PLAYBOOK_DIR"
  local kiro_dst="$KIRO_PB_GLOBAL"
  local bear_dst="$BEAR_PB_GLOBAL"

  if [[ -f "$kiro_dst" && "$FORCE" -ne 1 ]]; then
    warn "$kiro_dst already exists"
    read -r -p "   Overwrite? [y/N]: " ans
    case "$ans" in
      [Yy]*) : ;;
      *) __skip_kiro=1; warn "Skipped $kiro_dst (kept existing)";;
    esac
  fi
  if [[ -z "${__skip_kiro:-}" ]]; then
    render_kiro_template > "$kiro_dst"
    ok "Wrote $kiro_dst"
  fi

  if [[ -f "$bear_dst" && "$FORCE" -ne 1 ]]; then
    warn "$bear_dst already exists"
    read -r -p "   Overwrite? [y/N]: " ans2
    case "$ans2" in
      [Yy]*) : ;;
      *) __skip_bear=1; warn "Skipped $bear_dst (kept existing)";;
    esac
  fi
  if [[ -z "${__skip_bear:-}" ]]; then
    render_bear_template > "$bear_dst"
    ok "Wrote $bear_dst"
  fi
}

write_playbooks_to_repo() {
  local repo="$1"
  local codexdir="$repo/codex"
  mkdir -p "$codexdir"

  local kiro_dst="$codexdir/kiro.md"
  local bear_dst="$codexdir/bear.md"

  if [[ -f "$kiro_dst" && "$FORCE" -ne 1 ]]; then
    if [[ ${INTERACTIVE:-0} -eq 1 ]]; then
      read -r -p "kiro.md already exists. Overwrite? [y/N] " __ans || true
      case "${__ans:-N}" in y|Y) : ;; *) warn "Skipped: $kiro_dst"; __skip_kiro=1;; esac
    else
      warn "$kiro_dst already exists; use --force to overwrite"; __skip_kiro=1
    fi
  fi
  if [[ -z "${__skip_kiro:-}" ]]; then
    render_kiro_template > "$kiro_dst"
    ok "Wrote $kiro_dst"
  fi

  if [[ -f "$bear_dst" && "$FORCE" -ne 1 ]]; then
    if [[ ${INTERACTIVE:-0} -eq 1 ]]; then
      read -r -p "bear.md already exists. Overwrite? [y/N] " __ans2 || true
      case "${__ans2:-N}" in y|Y) : ;; *) warn "Skipped: $bear_dst"; __skip_bear=1;; esac
    else
      warn "$bear_dst already exists; use --force to overwrite"; __skip_bear=1
    fi
  fi
  if [[ -z "${__skip_bear:-}" ]]; then
    render_bear_template > "$bear_dst"
    ok "Wrote $bear_dst"
  fi
}

# ───────────────────────── interactive selections ─────────────────────────
parse_tiers_csv() {
  local csv="${1:-}"; local -a out=()
  if [[ -z "$csv" ]]; then csv="low,mid"; fi
  IFS=',' read -r -a parts <<<"$csv"
  for t in "${parts[@]}"; do case "$t" in min|low|mid|high) out+=("$t");; *) warn "Ignoring unknown tier: $t";; esac; done
  if [[ ${#out[@]} -eq 0 ]]; then out=(low mid); fi
  printf "%s\n" "${out[@]}"
}

select_tiers_interactive() {
  sep
  ce "install_codex_aliases.sh  v${VERSION} — interactive mode"
  sep
  ce "▌ Select reasoning tiers (comma-separated):"
  ce "▌  1) min (minimal)"
  ce "▌  2) low (low)"
  ce "▌  3) mid (medium)  (recommended default)"
  ce "▌  4) high (high)"
  read -r -p "Enter choices [default: low,mid]: " ans || true
  if [[ -z "${ans:-}" ]]; then TIERS_CSV="low,mid"
  else ans="${ans//1/min}"; ans="${ans//2/low}"; ans="${ans//3/mid}"; ans="${ans//4/high}"; TIERS_CSV="$ans"; fi
}

select_file_opener_interactive() {
  sep
  ce "▌ Choose your default file opener for clickable file links:"
  ce "▌  1) vscode (default)"
  ce "▌  2) vscode-insiders"
  ce "▌  3) windsurf"
  ce "▌  4) cursor"
  ce "▌  5) none"
  read -r -p "Enter choice [1-5, default: 1]: " ans || true
  case "${ans:-1}" in
    1) FILE_OPENER="vscode" ;;
    2) FILE_OPENER="vscode-insiders" ;;
    3) FILE_OPENER="windsurf" ;;
    4) FILE_OPENER="cursor" ;;
    5) FILE_OPENER="none" ;;
    *) warn "Unknown choice '${ans}', using default 'vscode'"; FILE_OPENER="vscode" ;;
  esac
}

# ───────────────────────── uninstall ─────────────────────────
uninstall_everything() {
  sep; info "Uninstalling aliases and playbooks (safe)"; sep
  rm -f "$KIRO_PB_GLOBAL" "$BEAR_PB_GLOBAL" || true
  ok "Removed global playbooks (if present)."

  local rcfile; rcfile="$(detect_shell_rc)"
  if grep -q "^# BEGIN CODEX ALIASES" "$rcfile" 2>/dev/null; then
    awk '
      /^# BEGIN CODEX ALIASES/ {skip=1}
      skip==0 {print}
      /^# END CODEX ALIASES/ {skip=0}
    ' "$rcfile" > "${rcfile}.tmp" && mv "${rcfile}.tmp" "$rcfile"
    ok "Removed alias block(s) from $rcfile"
  else
    warn "Alias block not found in $rcfile"
  fi

  # Remove installed profiles from ~/.codex/config.toml
  local cfg="${HOME}/.codex/config.toml"
  if [[ -f "$cfg" ]]; then
    info "Removing installed profiles from $cfg"
    cp "$cfg" "${cfg}.bak.$(date +%Y%m%d-%H%M%S)"
    awk '
      BEGIN{skip=0}
      /^\[profiles\.(kiro|min|low|mid|high)/ { }
      # Start skipping when a Kiro/Bear tiered profile section or its subtables begin
      /^\[profiles\.(kiro|bear)_(min|low|mid|high)\]$/ {skip=1; next}
      /^\[profiles\.(kiro|bear)_(min|low|mid|high)\./ {skip=1; next}
      # On any new TOML table header, stop skipping
      /^\[/ { if (skip==1) { skip=0 } }
      skip==0 { print }
    ' "$cfg" > "${cfg}.tmp" && mv "${cfg}.tmp" "$cfg"
    ok "Removed kiro_*/bear_* profiles from $cfg"
  fi
}

# ───────────────────────── main ─────────────────────────
main() {
  check_codex

  local INTERACTIVE=0
  if [[ -t 0 && -t 1 ]]; then INTERACTIVE=1; fi

  if [[ $DO_UNINSTALL -eq 1 ]]; then uninstall_everything; ok "Uninstall complete."; exit 0; fi

  if [[ $DO_CHECK -eq 1 ]]; then
    sep
    ce "Codex CLI: $(command -v codex)"
    ce "Model: ${CODEX_MODEL}"
    ce "Reasoning (min/low/mid/high): ${REASON_MIN}/${REASON_LOW}/${REASON_MID}/${REASON_HIGH}"
    ce "Global file_opener: ${FILE_OPENER} (pending write)"
    check_model_availability "${CODEX_MODEL}"
    if [[ -f "$HOME/.codex/config.toml" ]]; then
      local check_tiers=($(parse_tiers_csv "${TIERS_CSV}"))
      for tier in "${check_tiers[@]}"; do
        for role in kiro bear; do
          local profile="${role}_${tier}"
          if grep -q "^\[profiles\.${profile}\]" "$HOME/.codex/config.toml" 2>/dev/null; then
            [[ "$role" == "bear" ]] && verify_sandbox_config "$profile" || true
          fi
        done
      done
      sep
      ce "~/.codex/config.toml (profiles summary):"
      awk '/^\[profiles\./, /^$/' "$HOME/.codex/config.toml" >&2 || true
    else
      warn "No ~/.codex/config.toml found"
    fi
    local rcfile; rcfile="$(detect_shell_rc)"
  ce "Shell RC: $rcfile"
    local begin_marker="# BEGIN CODEX ALIASES"
    if grep -q "$begin_marker" "$rcfile" 2>/dev/null; then ok "Alias block present"; else warn "Alias block not found"; fi
    exit 0
  fi

  # Determine actions
  local NEEDS_FRESH_INSTALL=0
  local NEEDS_REPO_INSTALL=0

  if [[ $DO_FRESH -eq 1 ]]; then
    NEEDS_FRESH_INSTALL=1
  elif [[ $INTERACTIVE -eq 1 && $DO_CHECK -eq 0 && $DO_UNINSTALL -eq 0 ]]; then
    if [[ "$(ask_yes_no 'Proceed with global setup (profiles + aliases + playbooks)?' 'Y')" == "Y" ]]; then
      NEEDS_FRESH_INSTALL=1
    fi
  fi
  if [[ -n "${REPO_PATH_INPUT:-}" ]]; then
    NEEDS_REPO_INSTALL=1
  fi

  # Determine tiers
  if [[ -z "${TIERS_CSV:-}" && $INTERACTIVE -eq 1 ]]; then select_tiers_interactive; fi
  SELECTED_TIERS=($(parse_tiers_csv "$TIERS_CSV"))

  # If interactive and no CLI --file-opener provided, prompt for opener
  if [[ $INTERACTIVE -eq 1 && -z "${CLI_FILE_OPENER:-}" ]]; then
    select_file_opener_interactive
  fi

  # Fresh/global install
  if [[ $NEEDS_FRESH_INSTALL -eq 1 ]]; then
    sep
    ce "Using model and reasoning per tier:"
    ce "  model=${CODEX_MODEL}"
    ce "  reasoning: min=${REASON_MIN} low=${REASON_LOW} mid=${REASON_MID} high=${REASON_HIGH}"
    ce "  tiers=$(printf "%s," "${SELECTED_TIERS[@]}" | sed 's/,$//')"
    ce "  file_opener=${FILE_OPENER}"
    sep
    ensure_profiles
    write_global_file_opener
    install_shell_block
    write_playbooks_global

    # Health checks (post-creation)
    check_model_availability "${CODEX_MODEL}"
    for tier in "${SELECTED_TIERS[@]}"; do
      verify_sandbox_config "bear_${tier}"
    done
    ok "Global setup complete."
  fi

  # Optional repo prompts
  if [[ $NEEDS_REPO_INSTALL -eq 1 ]]; then
    REPO_PATH_INPUT="$(normalize_path "$REPO_PATH_INPUT")"
    [[ -d "$REPO_PATH_INPUT" ]] || { err "Path does not exist: $REPO_PATH_INPUT"; exit 1; }
    write_playbooks_to_repo "$REPO_PATH_INPUT"
  elif [[ $INTERACTIVE -eq 1 ]]; then
    # Offer to install repo playbooks interactively
    if [[ "$(ask_yes_no 'Also install repo playbooks into a project folder?' 'Y')" == "Y" ]]; then
      local repo_ans
      read -r -p "Enter project folder path [default: $(pwd)]: " repo_ans || true
      repo_ans="${repo_ans:-$(pwd)}"
      repo_ans="$(normalize_path "$repo_ans")"
      if [[ -d "$repo_ans" ]]; then
        write_playbooks_to_repo "$repo_ans"
      else
        warn "Provided path does not exist: $repo_ans (skipping repo playbooks)"
      fi
    fi
  fi

  sep
  ok "All done."
  ce "If you modified your shell rc, run: source \"$(detect_shell_rc)\""
  ce "Examples to run:"
  ce "  /kiro \"Draft requirements/design/tasks for Feature X (EARS style)\""
  ce "  /bear \"Implement task #3 from tasks.md; output minimal diff and run tests\""
}

main "$@"
