#!/usr/bin/env bash
# Enhanced Interactive Embedded Profile Functions
# Full Kiro & Bear with configurable tiers and interactive setup

set -euo pipefail


# ───────────────────────── Bash Version Check ─────────────────────────
# We require Bash >= 4.0 (associative arrays + readarray). macOS ships 3.2 by default.
# If your version is older, follow the printed instructions.
if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "❌ This script must be run with bash, not sh/zsh. Try: bash $0" >&2
  exit 1
fi
bash_major="${BASH_VERSINFO[0]}"
bash_minor="${BASH_VERSINFO[1]}"
if (( bash_major < 4 )); then
  cat <<'EOBASH'
❌ Your Bash version is too old for this installer (requires >= 4.0).

On macOS (Homebrew):
  brew install bash
  # then run with the brewed bash:
  /opt/homebrew/bin/bash path/to/this_script.sh

On Linux:
  # Ensure bash >= 4 is installed via your package manager, e.g.:
  sudo apt-get update && sudo apt-get install -y bash

If you still see this message, explicitly invoke the newer bash:
  /usr/bin/env bash path/to/this_script.sh
EOBASH
  exit 1
fi

VERSION="2.0.0"
SCRIPT_NAME="enhanced_embedded_profiles-${VERSION}.sh"

# ───────────────────────── helpers ─────────────────────────
ce(){ printf "%s\n" "$*" >&2; }
info(){ ce "👉 $*"; }
ok(){ ce "✅ $*"; }
warn(){ ce "⚠️  $*"; }
err(){ ce "❌ $*"; }
sep(){ ce "────────────────────────────────────────────────────"; }

usage() {
  cat <<EOF
Enhanced Embedded Profile Functions v${VERSION}

This script installs Kiro & Bear functions with embedded profile instructions,
bypassing the config.toml profile system entirely for maximum reliability.

Features:
  • Embedded profile instructions (no config.toml dependency)
  • Configurable reasoning tiers (min/low/mid/high)
  • Interactive or non-interactive installation
  • Optional startup messages
  • Comprehensive test functions

Usage:
  $0                          # Interactive mode
  $0 --auto                   # Non-interactive with defaults
  $0 --tiers min,low,mid      # Specific tiers only
  $0 --quiet                  # Silent installation
  $0 --uninstall              # Remove functions
  $0 --check                  # Show current status
  $0 --help                   # Show this help

Environment Variables:
  CODEX_MODEL=gpt-5           # Model to use
  CODEX_TIERS=min,low,mid,high # Tiers to install
  CODEX_QUIET=1               # Suppress startup messages
EOF
}

# ───────────────────────── Configuration ─────────────────────────
: "${CODEX_MODEL:="gpt-5"}"
: "${CODEX_TIERS:=""}"
: "${CODEX_QUIET:=""}"

# Reasoning effort mappings
declare -A REASONING_LEVELS=(
  ["min"]="minimal"
  ["low"]="low" 
  ["mid"]="medium"
  ["high"]="high"
)

# ───────────────────────── Arguments ─────────────────────────
INTERACTIVE=1
AUTO_MODE=0
QUIET_MODE=0
DO_UNINSTALL=0
DO_CHECK=0
SELECTED_TIERS=""

# Detect if running interactively
if [[ ! -t 0 || ! -t 1 ]]; then
  INTERACTIVE=0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto) AUTO_MODE=1; INTERACTIVE=0; shift ;;
    --tiers) SELECTED_TIERS="${2:-}"; shift 2 ;;
    --quiet) QUIET_MODE=1; shift ;;
    --uninstall) DO_UNINSTALL=1; shift ;;
    --check) DO_CHECK=1; shift ;;
    --mode)
      INSTALL_MODE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown argument: $1"; usage; exit 2 ;;
  esac
done

# Apply environment overrides
if [[ -n "$CODEX_TIERS" ]]; then
  SELECTED_TIERS="$CODEX_TIERS"
fi
if [[ -n "$CODEX_QUIET" ]]; then
  QUIET_MODE=1
fi

# ───────────────────────── Utilities ─────────────────────────
detect_shell_rc() {
  if [[ -n "${ZSH_VERSION-}" ]] || [[ "${SHELL-}" == *"/zsh" ]]; then
    echo "${HOME}/.zshrc"
  else
    echo "${HOME}/.bashrc"
  fi
}

ask_yes_no() {
  local prompt="${1:-Continue?}"
  local default="${2:-Y}"
  local ans
  
  if [[ $INTERACTIVE -eq 0 ]]; then
    echo "$default"
    return
  fi
  
  read -r -p "${prompt} [${default}/n]: " ans || true
  ans="${ans:-$default}"
  case "$ans" in
    Y|y|yes|YES) echo "Y" ;;
    *) echo "N" ;;
  esac
}


# Multiple-choice prompt for overwrite behavior
ask_overwrite_mode() {
  # Returns one of: O S D
  # O = Overwrite (replace existing block)
  # S = Skip (do nothing)
  # D = Delete first then install (clean slate)
  local prompt="${1:-Embedded functions already exist. Action?}"
  local default="${2:-O}"
  local ans
  if [[ $INTERACTIVE -eq 0 ]]; then
    echo "$default"
    return
  fi
  echo
  ce "$prompt"
  ce "  [O]verwrite  - Replace existing block (default)"
  ce "  [S]kip       - Leave as-is (no changes)"
  ce "  [D]elete+Add - Remove then re-install cleanly"
  read -r -p "Choose [O/S/D, default: ${default}]: " ans || true
  ans="${ans:-$default}"
  case "$ans" in
    O|o|overwrite|OVERWRITE) echo "O" ;;
    S|s|skip|SKIP)           echo "S" ;;
    D|d|delete|DELETE)       echo "D" ;;
    *) echo "O" ;;  # fallback
  esac
}


parse_tiers() {
  local input="${1:-}"
  local -a result=()

  if [[ -z "$input" ]]; then
    echo "mid"  # Default tier
    return
  fi

  IFS=',' read -r -a parts <<< "$input"
  for tier in "${parts[@]}"; do
    tier="$(echo "$tier" | xargs)"   # trim whitespace
    [[ -z "$tier" ]] && continue     # ignore empty tokens
    case "$tier" in
      1|min)   result+=("min") ;;
      2|low)   result+=("low") ;;
      3|mid)   result+=("mid") ;;
      4|high)  result+=("high") ;;
      5|all)   result=("min" "low" "mid" "high"); break ;;
      *)       warn "Ignoring unknown tier: $tier" ;;
    esac
  done

  if [[ ${#result[@]} -eq 0 ]]; then
    result=("mid")
  fi

  printf "%s\n" "${result[@]}"
}


# ───────────────────────── Interactive Selections ─────────────────────────
select_tiers_interactive() {
  sep
  ce "Enhanced Embedded Profile Installer v${VERSION}"
  sep
  ce "Select reasoning tiers to install:"
  ce "  1) min     - Minimal reasoning (fastest, basic tasks)"
  ce "  2) low     - Low reasoning (quick, simple tasks)"
  ce "  3) mid     - Medium reasoning (balanced, recommended)"
  ce "  4) high    - High reasoning (thorough, complex tasks)"
  ce "  5) all     - All tiers (min,low,mid,high)"
  echo
  
  local choice
  read -r -p "Enter choices [1-5 or comma-separated like '2,3,4', default: 3]: " choice || true
  
  case "${choice:-3}" in
    1) SELECTED_TIERS="min" ;;
    2) SELECTED_TIERS="low" ;;
    3) SELECTED_TIERS="mid" ;;
    4) SELECTED_TIERS="high" ;;
    5) SELECTED_TIERS="min,low,mid,high" ;;
    *) 
      # Parse comma-separated or multiple numbers
      choice="${choice//1/min,}"
      choice="${choice//2/low,}"
      choice="${choice//3/mid,}"
      choice="${choice//4/high,}"
      choice="${choice//5/min,low,mid,high,}"
      choice="${choice%,}"  # Remove trailing comma
      SELECTED_TIERS="$choice"
      ;;
  esac
  
  if [[ -z "$SELECTED_TIERS" ]]; then
    SELECTED_TIERS="mid"
  fi
}

select_options_interactive() {
  sep
  ce "Installation Options:"
  
  if [[ "$(ask_yes_no "Show startup confirmation messages when functions load?" "Y")" == "N" ]]; then
    QUIET_MODE=1
  fi
  
  echo
  ce "Model: $CODEX_MODEL"
  if [[ "$(ask_yes_no "Change model from $CODEX_MODEL?" "N")" == "Y" ]]; then
    read -r -p "Enter model name [gpt-5]: " new_model || true
    CODEX_MODEL="${new_model:-gpt-5}"
  fi
}

# ───────────────────────── Profile Templates ─────────────────────────
generate_kiro_profile() {
  local tier="$1"
  local reasoning="${REASONING_LEVELS[$tier]}"
  
  cat <<EOF
# Kiro (Codex CLI) — STRICT Planning & Artifacts (No Chain-of-Thought)

**Runtime:** Codex CLI profile kiro_${tier} (model: ${CODEX_MODEL}, reasoning: ${reasoning}).
**Goal:** Maintain requirements.md, design.md, tasks.md via preview → APPROVE/REVISE → write loops.
**Resumable:** On re-run, read existing files and propose concise diffs.

## HARD RULE — NEVER edit code files
Kiro must not create/modify/delete code files. It only writes these artifacts after APPROVE:
- requirements.md
- design.md  
- tasks.md

If the user asks to modify code, reply with a single line:
SWITCH TO BEAR: bear-${tier} "<ABSOLUTE_PATH_TO_tasks.md>"

## Behavior
- Be concise. Do not print chain-of-thought. Ask ≤2 clarifying questions only if essential.
- Prefer EARS-style requirements; keep traceability light.
- When updating, show a minimal diff before writing.
- Always re-read existing markdowns and update incrementally.

## Flow
1) Requirements PREVIEW (bulleted): scope, constraints, acceptance criteria (IDs).
   Wait for APPROVE or REVISE. If APPROVE → write requirements.md.
2) Design PREVIEW (bulleted): components, integration points, risks/mitigations.
   Wait for APPROVE or REVISE. If APPROVE → write design.md.
3) Tasks PREVIEW: numbered, small, testable tasks, reference AC IDs.
   Wait for APPROVE or REVISE. If APPROVE → write/merge tasks.md.

After writing/merging tasks.md, output a ready-to-paste handoff line (using the absolute path):
SWITCH TO BEAR: bear-${tier} "<ABSOLUTE_PATH_TO_tasks.md>"

## Decision Prompt
At the end of each PREVIEW, include exactly:
DECIDE → Reply exactly with one of:
- APPROVE
- REVISE: <your changes or constraints>
- CANCEL

========================= USER TASK =========================
EOF
}

generate_bear_profile() {
  local tier="$1"
  local reasoning="${REASONING_LEVELS[$tier]}"
  
  cat <<EOF
# Bear (Codex CLI) — Lean Executor (No Chain-of-Thought)

**Runtime:** Codex CLI profile bear_${tier} (model: ${CODEX_MODEL}, reasoning: ${reasoning}).
**Purpose:** Implement tasks from tasks.md (or a provided task) with small patches and quick validation.

## Behavior
- Be concise. Do not print chain-of-thought.
- Start with a micro-plan (3–6 bullets). Reference tasks.md item IDs.
- Produce patch-ready diffs (unified) or exact file blocks; favor small, testable increments.
- Run/validate when appropriate; summarize results; propose the next step.

## Optional Confirmation (for risky/large changes)
Show the diff first, then wait:
APPLY? → Reply exactly with:
- APPLY
- REVISE: <what to change>
- CANCEL

If the user replies AUTO once in this run, proceed without further confirmations.

========================= USER TASK =========================
EOF
}

# ───────────────────────── Function Generation ─────────────────────────
generate_functions() {
  local -a tiers=()
  readarray -t tiers < <(parse_tiers "$SELECTED_TIERS")
  
  # Generate header
  cat <<EOF
# BEGIN EMBEDDED CODEX FUNCTIONS v${VERSION}
# Generated: $(date)
# Tiers: ${tiers[*]}
# Model: $CODEX_MODEL
# Quiet Mode: $QUIET_MODE

EOF

  # Generate default shortcuts (always point to mid if available, otherwise first tier)
  local default_tier="mid"
  if [[ ! " ${tiers[*]} " == *" mid "* ]]; then
    default_tier="${tiers[0]}"
  fi
  
  cat <<EOF
# Default shortcuts
kiro() { kiro-${default_tier} "\$@"; }
bear() { bear-${default_tier} "\$@"; }

EOF

  # Generate tier-specific functions
  for tier in "${tiers[@]}"; do
    local reasoning="${REASONING_LEVELS[$tier]}"
    
    cat <<EOF
kiro-${tier}() {
    echo "🎯 KIRO-${tier^^}: Strategic Planning (${reasoning^} Reasoning)"
    if command -v codex >/dev/null 2>&1; then
        codex \\
            --sandbox read-only \\
            --ask-for-approval untrusted \\
            --model ${CODEX_MODEL} \\
            --config model_reasoning_effort=${reasoning} \\
            "\$(cat << 'KIRO_PROFILE'
$(generate_kiro_profile "$tier")
KIRO_PROFILE
)

USER TASK: \$*"
    else
        echo "❌ Codex CLI not available"
    fi
}

bear-${tier}() {
    echo "⚡ BEAR-${tier^^}: Implementation (${reasoning^} Reasoning)"
    if command -v codex >/dev/null 2>&1; then
        codex \\
            --sandbox workspace-write \\
            --ask-for-approval on-request \\
            --model ${CODEX_MODEL} \\
            --config model_reasoning_effort=${reasoning} \\
            "\$(cat << 'BEAR_PROFILE'
$(generate_bear_profile "$tier")
BEAR_PROFILE
)

USER TASK: \$*"
    else
        echo "❌ Codex CLI not available"
    fi
}

EOF
  done

  # Generate test functions
  cat <<'EOF'
# Test functions
kiro-test() { kiro "Plan a simple todo application with user authentication"; }
bear-test() { bear "Create a basic hello.js file with console.log"; }

EOF

  # Generate tier-specific test functions
  for tier in "${tiers[@]}"; do
    case "$tier" in
      min) task="Plan a basic calculator app" ;;
      low) task="Plan a simple blog website" ;;
      mid) task="Plan a todo app with authentication" ;;
      high) task="Plan a scalable e-commerce platform" ;;
    esac
    
    echo "kiro-test-${tier}() { kiro-${tier} \"${task}\"; }"
    
    case "$tier" in
      min) task="Create hello world function" ;;
      low) task="Implement basic CRUD operations" ;;
      mid) task="Build authentication middleware" ;;
      high) task="Implement distributed caching system" ;;
    esac
    
    echo "bear-test-${tier}() { bear-${tier} \"${task}\"; }"
  done

  # Generate status function
  cat <<EOF

# Status and help functions
codex-status() {
    echo "=== Codex CLI Status with Embedded Profiles ==="
    echo "CLI Available: \$(command -v codex >/dev/null 2>&1 && echo 'YES' || echo 'NO')"
    echo "Version: \$(codex --version 2>/dev/null || echo 'UNKNOWN')"
    echo "Config: \$(test -f ~/.codex/config.toml && echo 'EXISTS' || echo 'MISSING')"
    echo "Auth: \$(test -f ~/.codex/auth.json && echo 'EXISTS' || echo 'MISSING')"
    echo "Embedded Functions: v${VERSION}"
    echo "Model: ${CODEX_MODEL}"
    echo "Installed Tiers: ${tiers[*]}"
    
    echo
    echo "🎯 KIRO Commands (Strategic Planning):"
    echo "  kiro 'task'       - Default (${default_tier} tier)"
EOF

  for tier in "${tiers[@]}"; do
    local reasoning="${REASONING_LEVELS[$tier]}"
    echo "    echo \"  kiro-${tier} 'task'   - ${reasoning^} reasoning\""
  done

  cat <<EOF
    
    echo
    echo "⚡ BEAR Commands (Implementation):"
    echo "  bear 'task'       - Default (${default_tier} tier)"
EOF

  for tier in "${tiers[@]}"; do
    local reasoning="${REASONING_LEVELS[$tier]}"
    echo "    echo \"  bear-${tier} 'task'   - ${reasoning^} reasoning\""
  done

  cat <<EOF
    
    echo
    echo "🧪 Test Commands:"
    echo "  kiro-test         - Test default planning"
    echo "  bear-test         - Test default implementation"
EOF

  for tier in "${tiers[@]}"; do
    echo "    echo \"  kiro-test-${tier}      - Test ${tier} tier planning\""
    echo "    echo \"  bear-test-${tier}      - Test ${tier} tier implementation\""
  done

  cat <<'EOF'
    
    echo
    echo "🔧 Utility Commands:"
    echo "  codex-status      - Show this status"
    echo "  codex-help        - Show usage examples"
}

codex-help() {
    echo "=== Codex Kiro & Bear Usage Examples ==="
    echo
    echo "🎯 Strategic Planning (Kiro):"
    echo "  kiro 'Plan a REST API for user management'"
    echo "  kiro-high 'Design microservice architecture for payments'"
    echo "  kiro-min 'Plan a simple contact form'"
    echo
    echo "⚡ Implementation (Bear):"
    echo "  bear 'Implement the login endpoint'"
    echo "  bear-high 'Build comprehensive error handling system'"
    echo "  bear-min 'Create basic HTML structure'"
    echo
    echo "🔄 Workflow:"
    echo "  1. Use Kiro to plan: kiro 'Plan feature X'"
    echo "  2. Approve requirements, design, tasks"
    echo "  3. Switch to Bear: bear 'Implement task #1 from tasks.md'"
    echo "  4. Review and approve implementation"
}

EOF

  # Add startup message (conditional)
  if [[ $QUIET_MODE -eq 0 ]]; then
    cat <<EOF
# Startup confirmation
echo "✅ Embedded Profile Functions Loaded (v${VERSION})"
echo "   Tiers: ${tiers[*]}"
echo "   Model: ${CODEX_MODEL}"
echo "   Run 'codex-status' for all commands"
EOF
  fi

  # Generate footer
  cat <<EOF
# END EMBEDDED CODEX FUNCTIONS
EOF
}

# ───────────────────────── Installation ─────────────────────────

install_functions() {
  local rcfile
  rcfile="$(detect_shell_rc)"
  info "Installing to: $rcfile"

  # Backup existing file
  if [[ -f "$rcfile" ]]; then
    cp "$rcfile" "${rcfile}.bak.$(date +%Y%m%d-%H%M%S)"
    ok "Backed up existing $rcfile"
  fi

  # Parse selected tiers now
  local -a selected_tiers=()
  readarray -t selected_tiers < <(parse_tiers "$SELECTED_TIERS")

  # Detect existing block & tiers
  local have_block=0
  local -a existing_tiers=()
  if [[ -f "$rcfile" ]] && grep -q "# BEGIN EMBEDDED CODEX FUNCTIONS" "$rcfile" 2>/dev/null; then
    have_block=1
    local tiers_line
    tiers_line="$(grep -m1 "^# Tiers:" "$rcfile" 2>/dev/null | sed 's/^# Tiers:[[:space:]]*//')"
    if [[ -n "$tiers_line" ]]; then
      # split by space
      read -r -a existing_tiers <<< "$tiers_line"
    fi
  fi

  # Compute set relations
  local -A seen=()
  local -a new_tiers=()
  for t in "${selected_tiers[@]}"; do
    local found=0
    for e in "${existing_tiers[@]}"; do
      [[ "$t" == "$e" ]] && found=1 && break
    done
    if [[ $found -eq 0 ]]; then
      new_tiers+=("$t")
    fi
  done

  if [[ $have_block -eq 1 ]]; then
    if [[ ${#new_tiers[@]} -gt 0 ]]; then
      # We have new tiers on top of installed ones -> propose union install
      ce "Existing tiers: ${existing_tiers[*]:-(none)}"
      ce "New tiers to add: ${new_tiers[*]}"
      ce "Final tiers will be: ${existing_tiers[*]} ${new_tiers[*]}"
      local mode
      if [[ -n "$INSTALL_MODE" ]]; then
      case "$INSTALL_MODE" in
        overwrite) mode="O" ;;
        skip) mode="S" ;;
        delete) mode="D" ;;
        *) mode="O" ;;
      esac
    else
      mode="$(ask_overwrite_mode "Reinstall to include new tiers as well. Proceed?" "O")"
    fi
      case "$mode" in
        S)
          warn "Skip selected. Leaving existing install unchanged."
          return 0
          ;;
        D|O)
          # Remove the old block, then regenerate with union of tiers
          sed -i.tmp '/# BEGIN EMBEDDED CODEX FUNCTIONS/,/# END EMBEDDED CODEX FUNCTIONS/d' "$rcfile"
          rm -f "${rcfile}.tmp"
          # Build union string preserving existing order then appending new
          local final_tiers=""
          if [[ ${#existing_tiers[@]} -gt 0 ]]; then
            final_tiers="${existing_tiers[*]}"
          fi
          if [[ ${#new_tiers[@]} -gt 0 ]]; then
            final_tiers="${final_tiers:+$final_tiers }${new_tiers[*]}"
          fi
          SELECTED_TIERS="$(echo "$final_tiers" | sed 's/[[:space:]]\+/,/g')"
          ;;
      esac
    else
      # Same set (no new tiers) → ask O/S/D
      local mode
      if [[ -n "$INSTALL_MODE" ]]; then
      case "$INSTALL_MODE" in
        overwrite) mode="O" ;;
        skip) mode="S" ;;
        delete) mode="D" ;;
        *) mode="S" ;;
      esac
    else
      mode="$(ask_overwrite_mode "Embedded functions already exist with same tiers. Action?" "S")"
    fi
      case "$mode" in
        S) warn "Keeping current install. No changes."; return 0 ;;
        D|O)
          sed -i.tmp '/# BEGIN EMBEDDED CODEX FUNCTIONS/,/# END EMBEDDED CODEX FUNCTIONS/d' "$rcfile"
          rm -f "${rcfile}.tmp"
          ;;
      esac
    fi
  fi

  # Add new functions (fresh or after removal)
  generate_functions >> "$rcfile"
  ok "Installed embedded functions"

  echo
  info "Installation complete! Next steps:"
  ce "  1. Run: source \"$rcfile\""
  ce "  2. Test: codex-status"
  ce "  3. Try: kiro-test"
}


# ───────────────────────── Uninstall ─────────────────────────



uninstall_functions() {
  local rcfile
  rcfile="$(detect_shell_rc)"

  if [[ -f "$rcfile" ]] && grep -q "# BEGIN EMBEDDED CODEX FUNCTIONS" "$rcfile" 2>/dev/null; then
    local do_backup
    do_backup="$(ask_yes_no "Create a backup before uninstalling?" "Y")"
    local backup_dir=""
    if [[ "$do_backup" == "Y" ]]; then
      local default_dir
      default_dir="$(dirname "$rcfile")"
      read -r -p "Enter backup directory [${default_dir}]: " backup_dir
      backup_dir="${backup_dir:-$default_dir}"
      mkdir -p "$backup_dir"
      local backup_file="${backup_dir}/$(basename "$rcfile").backup.$(date +%Y%m%d-%H%M%S)"
      cp "$rcfile" "$backup_file"
      ok "Backup created at $backup_file"
    else
      warn "No backup created"
    fi

    sed -i.tmp '/# BEGIN EMBEDDED CODEX FUNCTIONS/,/# END EMBEDDED CODEX FUNCTIONS/d' "$rcfile"
    rm -f "${rcfile}.tmp"
    ok "Removed embedded functions from $rcfile"
    info "Run: source \"$rcfile\" to reload your shell"
  else
    warn "No embedded functions found in $rcfile"
  fi
}




# ───────────────────────── Status Check ─────────────────────────
check_status() {
  local rcfile
  rcfile="$(detect_shell_rc)"
  
  sep
  ce "Embedded Profile Functions Status"
  sep
  
  if [[ -f "$rcfile" ]] && grep -q "# BEGIN EMBEDDED CODEX FUNCTIONS" "$rcfile" 2>/dev/null; then
    ok "Embedded functions installed in $rcfile"
    
    # Extract version and tiers
    local version_line
    version_line=$(grep "# Generated:" "$rcfile" 2>/dev/null || echo "Unknown version")
    ce "  $version_line"
    
    local tiers_line
    tiers_line=$(grep "# Tiers:" "$rcfile" 2>/dev/null || echo "Unknown tiers")
    ce "  $tiers_line"
    
    local model_line
    model_line=$(grep "# Model:" "$rcfile" 2>/dev/null || echo "Unknown model")
    ce "  $model_line"
  else
    warn "No embedded functions found"
  fi
  
  # Check if functions are loaded in current session
  if declare -f kiro >/dev/null 2>&1; then
    ok "Functions loaded in current session"
  else
    warn "Functions not loaded (run: source \"$rcfile\")"
  fi
  
  # Check Codex CLI
  if command -v codex >/dev/null 2>&1; then
    ok "Codex CLI available: $(command -v codex)"
    ce "  Version: $(codex --version 2>/dev/null || echo 'unknown')"
  else
    err "Codex CLI not found"
  fi
}

# ───────────────────────── Main ─────────────────────────
main() {
  # Handle special modes first
  if [[ $DO_UNINSTALL -eq 1 ]]; then
    uninstall_functions
    exit 0
  fi
  
  if [[ $DO_CHECK -eq 1 ]]; then
    check_status
    exit 0
  fi
  
  # Interactive mode
  if [[ $INTERACTIVE -eq 1 && $AUTO_MODE -eq 0 ]]; then
    sep
    ce "Enhanced Embedded Profile Installer v${VERSION}"
    ce "Bypasses config.toml for maximum reliability"
    sep
    
    if [[ "$(ask_yes_no "Proceed with interactive installation?" "Y")" == "N" ]]; then
      ce "Installation cancelled"
      exit 0
    fi
    
    select_tiers_interactive
    select_options_interactive
  else
    # Auto mode - use defaults or environment
    if [[ -z "$SELECTED_TIERS" ]]; then
      SELECTED_TIERS="mid"
    fi
  fi
  
  # Show installation summary
  local -a tiers=()
  readarray -t tiers < <(parse_tiers "$SELECTED_TIERS")
  
  sep
  ce "Installation Summary:"
  ce "  Tiers: ${tiers[*]}"
  ce "  Model: $CODEX_MODEL"
  ce "  Quiet: $QUIET_MODE"
  ce "  Shell: $(detect_shell_rc)"
  sep
  
  if [[ $INTERACTIVE -eq 1 && "$(ask_yes_no "Proceed with installation?" "Y")" == "N" ]]; then
    ce "Installation cancelled"
    exit 0
  fi
  
  # Install
  install_functions
}

main "$@"