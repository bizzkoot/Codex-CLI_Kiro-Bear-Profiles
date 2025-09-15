#!/usr/bin/env bash
# Enhanced Interactive Embedded Profile Functions v2.0.5
# CHANGES (v2.0.5):
# - Interactive model selection: Choose between 'gpt-5' and 'gpt-5-codex'.
# - Conditional reasoning tiers: 'gpt-5-codex' offers 'low', 'mid', 'high' tiers.
# Full Kiro & Bear with configurable tiers and interactive setup

set -euo pipefail

# ─────────────────────────────── Bash Version Check ───────────────────────────────
if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "⚠️  This script must be run with bash, not sh/zsh. Try: bash $0" >&2
  exit 1
fi
bash_major="${BASH_VERSINFO[0]}"
if (( bash_major < 4 )); then
  cat <<'EOBASH'
⚠️  Your Bash version is too old for this installer (requires >= 4.0).

On macOS (Homebrew):
  brew install bash
  /opt/homebrew/bin/bash path/to/this_script.sh

On Linux:
  sudo apt-get update && sudo apt-get install -y bash

If you still see this message, explicitly invoke the newer bash:
  /usr/bin/env bash path/to/this_script.sh
EOBASH
  exit 1
fi

VERSION="2.0.5"
SCRIPT_NAME="enhanced_embedded_profiles-${VERSION}.sh"

# ─────────────────────────────── helpers ───────────────────────────────
ce(){ printf "%s\n" "$*" >&2; }
info(){ ce "👉 $*"; }
ok(){ ce "✅ $*"; }
warn(){ ce "⚠️  $*"; }
err(){ ce "❌ $*"; }
sep(){ ce "──────────────────────────────────────────────────"; }

# Cross-platform sed in-place editing
safe_sed_inplace() {
  local pattern="$1"
  local file="$2"
  local tmpfile="${file}.tmp.$$"

  if sed "$pattern" "$file" > "$tmpfile"; then
    mv "$tmpfile" "$file"
  else
    rm -f "$tmpfile"
    return 1
  fi
}

usage() {
  cat <<EOF
Enhanced Embedded Profile Functions v${VERSION}

This script installs Kiro & Bear functions with embedded profile instructions,
bypassing the config.toml profile system entirely for maximum reliability.

Usage:
  $0                          # Interactive mode
  $0 --auto                   # Non-interactive with defaults
  $0 --tiers min,low,mid      # Specific tiers only
  $0 --quiet                  # Silent installation
  $0 --uninstall              # Remove functions
  $0 --check                  # Show current status
  $0 --version                # Show version
  $0 --help                   # Show this help

Environment Variables:
  CODEX_MODEL=gpt-5            # Model to use
  CODEX_TIERS=min,low,mid,high # Tiers to install
  CODEX_QUIET=1                # Suppress startup messages
  CODEX_FILE_OPENER=vscode|vscode-insiders|windsurf|cursor|none  # File opener for links
  CODEX_WEB_SEARCH=0|1         # Bear web access (0=off default, 1=on). Kiro always ON.

CLI Options:
  --file-opener OPENER         # One of: vscode, vscode-insiders, windsurf, cursor, none
EOF
}

# ─────────────────────────────── Configuration ───────────────────────────────
: "${CODEX_MODEL:="gpt-5"}"
: "${CODEX_TIERS:=""}"
: "${CODEX_QUIET:=""}"
: "${CODEX_FILE_OPENER:="vscode"}"
: "${CODEX_WEB_SEARCH:="0"}"   # Only used at runtime by Bear functions

# File opener (validated)
FILE_OPENER="$CODEX_FILE_OPENER"

# Reasoning effort mappings
declare -A REASONING_LEVELS=(
  [min]="minimal"
  [low]="low"
  [mid]="medium"
  [high]="high"
)

# ─────────────────────────────── Arguments ───────────────────────────────
INTERACTIVE=1
AUTO_MODE=0
QUIET_MODE=0
DO_UNINSTALL=0
DO_CHECK=0
DO_VERSION=0
SELECTED_TIERS=""
CLI_FILE_OPENER=""
INSTALL_MODE=""

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
    --version) DO_VERSION=1; shift ;;
    --file-opener) CLI_FILE_OPENER="${2:-}"; shift 2 ;;
    --mode) INSTALL_MODE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown argument: $1"; usage; exit 2 ;;
  esac
done

# Auto-mode validation
if [[ ${AUTO_MODE:-0} -eq 1 ]] && ! command -v codex >/dev/null 2>&1; then
    err "Codex CLI not found. Install or ensure it's on PATH."
    exit 1
fi

# Apply environment overrides
if [[ -n "$CODEX_TIERS" ]]; then
  SELECTED_TIERS="$CODEX_TIERS"
fi
if [[ -n "$CODEX_QUIET" ]]; then
  QUIET_MODE=1
fi
if [[ -n "$CLI_FILE_OPENER" ]]; then
  FILE_OPENER="$CLI_FILE_OPENER"
fi

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

# ─────────────────────────────── Utilities ───────────────────────────────
feature_slugify() {
  local s="$*"
  printf '%s' "$s" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

detect_shell_rc() {
  if [[ -n "${ZSH_VERSION-}" ]] || [[ "${SHELL-}" == *"/zsh" ]]; then
    echo "${HOME}/.zshrc"
  else
    if [[ -f "${HOME}/.bashrc" ]]; then
      echo "${HOME}/.bashrc"
    else
      echo "${HOME}/.bash_profile"
    fi
  fi
}

ask_yes_no() {
  local prompt="${1:-\"Continue?\"}"
  local default="${2:-\"Y\"}"
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

ask_overwrite_mode() {
  local prompt="${1:-\"Embedded functions already exist. Action?\"}"
  local default="${2:-\"O\"}"
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
    *) echo "O" ;;
  esac
}

parse_tiers() {
  local input="${1:-""}"
  local -a result=()

  if [[ -z "$input" ]]; then
    echo "mid"
    return
  fi

  IFS=',' read -r -a parts <<< "$input"
  for tier in "${parts[@]}"; do
    tier="$(echo "$tier" | xargs)"
    [[ -z "$tier" ]] && continue

    if [[ "$CODEX_MODEL" == "gpt-5-codex" ]]; then
      case "$tier" in
        1|low)   result+=("low") ;;
        2|mid)   result+=("mid") ;;
        3|high)  result+=("high") ;;
        4|all)   result=("low" "mid" "high"); break ;;
        min)     warn "Ignoring unsupported tier 'min' for model '$CODEX_MODEL'" ;;
        *)       warn "Ignoring unknown tier for '$CODEX_MODEL': $tier" ;;
      esac
    else # gpt-5
      case "$tier" in
        1|min)   result+=("min") ;;
        2|low)   result+=("low") ;;
        3|mid)   result+=("mid") ;;
        4|high)  result+=("high") ;;
        5|all)   result=("min" "low" "mid" "high"); break ;;
        *)       warn "Ignoring unknown tier: $tier" ;;
      esac
    fi
  done

  if [[ ${#result[@]} -eq 0 ]]; then
    result=("mid")
  fi

  printf "%s\n" "${result[@]}"
}


# ─────────────────────────────── Interactive Selections ───────────────────────────────
select_tiers_interactive() {
  sep
  ce "Enhanced Embedded Profile Installer v${VERSION}"
  sep
  ce "Select reasoning tiers to install for model '$CODEX_MODEL':"

  if [[ "$CODEX_MODEL" == "gpt-5-codex" ]]; then
    ce "  1) low     - Low reasoning (quick, simple tasks)"
    ce "  2) mid     - Medium reasoning (balanced, recommended)"
    ce "  3) high    - High reasoning (thorough, complex tasks)"
    ce "  4) all     - All tiers (low,mid,high)"
    echo

    local choice
    read -r -p "Enter choices [1-4 or comma-separated like '1,2,3', default: 2]: " choice || true

    case "${choice:-2}" in
      1) SELECTED_TIERS="low" ;;
      2) SELECTED_TIERS="mid" ;;
      3) SELECTED_TIERS="high" ;;
      4) SELECTED_TIERS="low,mid,high" ;;
      *)
        choice="${choice//1/low,}"
        choice="${choice//2/mid,}"
        choice="${choice//3/high,}"
        choice="${choice//4/low,mid,high,}"
        choice="${choice%,}"
        SELECTED_TIERS="$choice"
        ;;
    esac

    if [[ -z "$SELECTED_TIERS" ]]; then
      SELECTED_TIERS="mid"
    fi
  else # gpt-5 (default)
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
        choice="${choice//1/min,}"
        choice="${choice//2/low,}"
        choice="${choice//3/mid,}"
        choice="${choice//4/high,}"
        choice="${choice//5/min,low,mid,high,}"
        choice="${choice%,}"
        SELECTED_TIERS="$choice"
        ;;
    esac

    if [[ -z "$SELECTED_TIERS" ]]; then
      SELECTED_TIERS="mid"
    fi
  fi
}

select_options_interactive() {
  sep
  ce "Installation Options:"

  if [[ "$(ask_yes_no "Show startup confirmation messages when functions load?" "Y")" == "N" ]]; then
    QUIET_MODE=1
  fi

  echo
  ce "Select model:"
  ce "  1) gpt-5 (default, 4 reasoning tiers)"
  ce "  2) gpt-5-codex (3 reasoning tiers: low, mid, high)"
  local model_choice
  read -r -p "Choose [1-2, default: 1]: " model_choice || true
  case "${model_choice:-1}" in
    1) CODEX_MODEL="gpt-5" ;;
    2) CODEX_MODEL="gpt-5-codex" ;;
    *) CODEX_MODEL="gpt-5"; warn "Unknown choice, defaulting to 'gpt-5'" ;;
  esac
  ce "Model set to: $CODEX_MODEL"

  echo
  # Direct selection of file opener with dynamic default as current value
  local __default_idx="1"
  case "$FILE_OPENER" in
    vscode) __default_idx="1" ;;
    vscode-insiders) __default_idx="2" ;;
    windsurf) __default_idx="3" ;;
    cursor) __default_idx="4" ;;
    none) __default_idx="5" ;;
  esac
  ce "Select file opener for clickable links:"
  ce "  1) vscode"
  ce "  2) vscode-insiders"
  ce "  3) windsurf"
  ce "  4) cursor"
  ce "  5) none"
  read -r -p "Choose [1-5, default: ${__default_idx}]: " __fo || true
  case "${__fo:-$__default_idx}" in
    1) FILE_OPENER="vscode" ;;
    2) FILE_OPENER="vscode-insiders" ;;
    3) FILE_OPENER="windsurf" ;;
    4) FILE_OPENER="cursor" ;;
    5) FILE_OPENER="none" ;;
    *) warn "Unknown choice '${__fo}', keeping '$FILE_OPENER'" ;;
  esac
}

# ─────────────────────────────── Profile Templates ───────────────────────────────
generate_kiro_profile() {
  local tier="$1"
  local reasoning="${REASONING_LEVELS[$tier]}"

  cat <<EOF
# Kiro (Codex CLI) — STRICT Planning & Artifacts

**Runtime:** Codex CLI profile kiro_${tier} (model: ${CODEX_MODEL}, reasoning: ${reasoning}).
**Goal:** Maintain /specs/{feature-slug}/00_requirements.md, 10_design.md, 20_tasks.md via preview → APPROVE/REVISE → write loops.
**Resumable:** On re-run, read existing files and propose concise diffs.
**Location:** All artifacts live under /specs/{feature-slug}/ (kebab-case from feature name; confirm once).

## HARD RULE — NEVER edit code files
Kiro must not create/modify/delete code files. It only writes these artifacts after APPROVE:
- 00_requirements.md
- 10_design.md
- 20_tasks.md

If asked to modify code, reply exactly:
SWITCH TO BEAR: bear-${tier} "<ABSOLUTE_PATH_TO_/specs/{feature-slug}/20_tasks.md>"

## Behavior
- Be concise; ask ≤2 clarifying Qs only if essential.
- Prefer EARS-style acceptance criteria; keep traceability light.
- Show minimal diffs before writing.
- Always re-read existing markdowns and update incrementally.
- For 20_tasks.md, format each item as
N. [ ] ... (AC-ID)
 (checkboxes + numbering).

## Flow
1) Requirements PREVIEW: scope, constraints, acceptance criteria (IDs).
   On APPROVE → write/merge 00_requirements.md.
2) Design PREVIEW: components, integration points, risks/mitigations.
   On APPROVE → write/merge 10_design.md.
3) Tasks PREVIEW: numbered + [ ] checkboxes, small/testable, reference AC IDs.
   On APPROVE → write/merge 20_tasks.md.

After writing 20_tasks.md, output handoff:
SWITCH TO BEAR: bear-${tier} "<ABSOLUTE_PATH_TO_/specs/{feature-slug}/20_tasks.md>"

## Numbered Files Rationale
Clear lifecycle order, easy insertions, CI-friendly globbing.

## Decision Prompt
At end of each PREVIEW, include exactly:
DECIDE → Reply exactly with:
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
# Bear (Codex CLI) — Lean Executor

**Runtime:** Codex CLI profile bear_${tier} (model: ${CODEX_MODEL}, reasoning: ${reasoning}).
**Purpose:** Execute tasks from /specs/{slug}/20_tasks.md with small, testable changes.

## Input
- Handoff: absolute path from Kiro (optional).
- Slug: resolve to
${PWD}/specs/{slug}/20_tasks.md.
- Fallback: choose most recent non-archived: /specs/**/20_tasks.md (exclude /specs/Done/**).

## Missing-Tasks Flow (Option 2)
If no non-archived 20_tasks.md is found:
1) Derive {slug} (kebab-case from feature name; confirm once).
2) Create stub at /specs/{slug}/20_tasks.md:


\`\`\`markdown
# Tasks
1. [ ] <short title> (AC-01)
   - intent: <1 line>
   - files: <paths if known>
   - test: <how to verify>
\`\`\`

3) Print a 3-line plan (title / files / test).
4) Ask **one** confirm only if anything is ambiguous or risky:
- Confirm? REPLY: APPROVE / REVISE:<edits> / CANCEL
- If AUTO: proceed unless risky/large.

## Behavior
- Be concise.
- Read 00_requirements.md, 10_design.md, 20_tasks.md if present.
- Start with a micro-plan (≤5 bullets) referencing task numbers.
- Output small diffs or file blocks; run & summarize checks when relevant.
- For 20_tasks.md:
- Match by number+text; flip
[ ]
 →
[x]
 only after success.
- Append "— done: <ISO8601> by Bear" once; keep numbering/format.
- Commit msg:
\`tasks: check off N. <title> (AC-XX)\`.
- If a change doesn't map, log under **Unmapped Completions**.

## Print Plan (compact)
- Show table with: N | title | files | test (1—3 lines total).
- Ask at most one clarification if needed; otherwise proceed.

## Archive (optional)
When all tasks
[x]
 (or ARCHIVE):
- Move 00/10/20 to /specs/Done/{DD-MM-YYYY}_{slug}/
- (Optional) update /specs/_index.md
- On APPROVE → perform and print path.

## Decision Prompt
At decision points (missing-tasks stub, risky diffs, archive):
DECIDE → Reply exactly with:
- APPROVE
- REVISE: <what to change>
- CANCEL
- AUTO   (run without further prompts, except pause for risky/large changes)

========================= USER TASK =========================
EOF
}

# ─────────────────────────────── Function Generation ───────────────────────────────
generate_functions() {
  local -a tiers=()
  readarray -t tiers < <(parse_tiers "$SELECTED_TIERS")

  # Generate header
  cat <<EOF
# BEGIN EMBEDDED CODEX FUNCTIONS v${VERSION}
# Generated: $(date)
# Tiers: ${tiers[*]}
# Model: $CODEX_MODEL
# File Opener (default): $FILE_OPENER
# Web Search: Kiro=ON, Bear=ENV (CODEX_WEB_SEARCH=0)

EOF

  # Generate default shortcuts
  local default_tier="mid"
  if [[ ! " ${tiers[*]} " =~ " mid " ]]; then
    default_tier="${tiers[0]}"
  fi

  cat <<EOF
# Default shortcuts
kiro() { kiro-${default_tier} "\$@"; }
bear() { bear-${default_tier} "\$@"; }

EOF

  # Generate tier-specific functions with inlined profiles
  for tier in "${tiers[@]}"; do
    local reasoning="${REASONING_LEVELS[$tier]}"
    local kiro_profile_body
    kiro_profile_body=$(generate_kiro_profile "$tier")
    local bear_profile_body
    bear_profile_body=$(generate_bear_profile "$tier")

    # KIRO FUNCTION
    cat <<EOF
kiro-${tier}() {
    echo "🎯 KIRO-${tier^^}: Strategic Planning (${reasoning^} Reasoning)"
    if command -v codex >/dev/null 2>&1; then
        local __FO="\${CODEX_FILE_OPENER:-${FILE_OPENER}}"
        local kiro_prompt=\$(cat <<'KIRO_TEXT'
${kiro_profile_body}
KIRO_TEXT
)
        codex \\
            --sandbox read-only \\
            --ask-for-approval untrusted \\
            --model "${CODEX_MODEL}" \\
            --config model_reasoning_effort=${reasoning} \\
            --config model_verbosity=low \\
            --config "file_opener=\${__FO}" \\
            --config tools.web_search=true \\
            "\$kiro_prompt

USER TASK: \$@" || return \$?
    else
        echo "❌ Codex CLI not available"; return 127
    fi
}
EOF

    # BEAR FUNCTION
    cat <<EOF
bear-${tier}() {
    echo "⚡ BEAR-${tier^^}: Implementation (${reasoning^} Reasoning)"
    if command -v codex >/dev/null 2>&1; then
        local __FO="\${CODEX_FILE_OPENER:-${FILE_OPENER}}"
        local __WS_env="\${CODEX_WEB_SEARCH:-0}"
        local __WS_bool="false"
        if [[ "\$__WS_env" == "1" ]]; then
            __WS_bool="true"
        fi
        local bear_prompt=\$(cat <<'BEAR_TEXT'
${bear_profile_body}
BEAR_TEXT
)
        codex \\
            --sandbox workspace-write \\
            --ask-for-approval on-request \\
            --model "${CODEX_MODEL}" \\
            --config model_reasoning_effort=${reasoning} \\
            --config model_verbosity=medium \\
            --config "file_opener=\${__FO}" \\
            --config "tools.web_search=\${__WS_bool}" \\
            "\$bear_prompt

USER TASK: \$@" || return \$?
    else
        echo "❌ Codex CLI not available"; return 127
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

  for tier in "${tiers[@]}"; do
    local kiro_task
    local bear_task
    case "$tier" in
      min) kiro_task="Plan a basic calculator app"; bear_task="Create hello world function" ;;
      low) kiro_task="Plan a simple blog website"; bear_task="Implement basic CRUD operations" ;;
      mid) kiro_task="Plan a todo app with authentication"; bear_task="Build authentication middleware" ;;
      high) kiro_task="Plan a scalable e-commerce platform"; bear_task="Implement distributed caching system" ;;
    esac
    cat <<EOF
kiro-test-${tier}() { kiro-${tier} "${kiro_task}"; }
bear-test-${tier}() { bear-${tier} "${bear_task}"; }
EOF
  done

  # Generate status and help functions
  cat <<EOF

# Status and help functions
codex-status() {
    local __FO="\${CODEX_FILE_OPENER:-${FILE_OPENER}}"
    local __WS="\${CODEX_WEB_SEARCH:-0}"
    echo "=== Codex CLI Status with Embedded Profiles ==="
    echo "CLI Available: \$(command -v codex >/dev/null 2>&1 && echo 'YES' || echo 'NO')"
    echo "Version: \$(codex --version 2>/dev/null || echo 'UNKNOWN')"
    echo "Config: \$(test -f ~/.codex/config.toml && echo 'EXISTS' || echo 'MISSING')"
    echo "Auth: \$(test -f ~/.codex/auth.json && echo 'EXISTS' || echo 'MISSING')"
    echo "Embedded Functions: v${VERSION}"
    echo "Model: ${CODEX_MODEL}"
    echo "File Opener (runtime): \${__FO}"
    echo "Installed Tiers: ${tiers[*]}"
    echo "Web Search: Kiro=ON, Bear=\${__WS} (override per-call: CODEX_WEB_SEARCH=1 bear '...')"

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

  cat <<'EOF'

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
    echo "  CODEX_WEB_SEARCH=1 bear 'Investigate a breaking change'"
    echo "  bear-min 'Create basic HTML structure'"
    echo
    echo "📄 Workflow:"
    echo "  1. Use Kiro to plan: kiro 'Plan feature X'"
    echo "  2. Approve requirements, design, tasks"
    echo "  3. Switch to Bear: bear 'Implement task #1 from tasks.md'"
    echo "  4. For external info during Bear: prefix with CODEX_WEB_SEARCH=1"
}

EOF

  # Generate startup banner
  if [[ $QUIET_MODE -eq 0 ]]; then
    cat <<EOF
# Startup confirmation
echo "✅ Embedded Profile Functions Loaded (v${VERSION})"
echo "   Tiers: ${tiers[*]}"
echo "   Model: ${CODEX_MODEL}"
echo "   Default opener: ${FILE_OPENER} (override at runtime via CODEX_FILE_OPENER)"
echo "   Tip: 'codex-status' to inspect; 'CODEX_WEB_SEARCH=1 bear \"...\"' to enable Bear web search"
EOF
  fi

  # Generate footer
  cat <<EOF
# END EMBEDDED CODEX FUNCTIONS
EOF
}


# ─────────────────────────────── Installation ───────────────────────────────

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
      read -r -a existing_tiers <<< "$tiers_line"
    fi
  fi

  # Compute set relations
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
      ce "Existing tiers: ${existing_tiers[*]:-(none)}"
      ce "New tiers to add: ${new_tiers[*]}"
      ce "Final tiers will be: ${existing_tiers[*]} ${new_tiers[*]}"
      local mode
      if [[ -n "${INSTALL_MODE:-}" ]]; then
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
          if ! safe_sed_inplace '/# BEGIN EMBEDDED CODEX FUNCTIONS/,/# END EMBEDDED CODEX FUNCTIONS/d' "$rcfile"; then
            err "Failed to remove existing functions from $rcfile"
            return 1
          fi
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
      local mode
      if [[ -n "${INSTALL_MODE:-}" ]]; then
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
          if ! safe_sed_inplace '/# BEGIN EMBEDDED CODEX FUNCTIONS/,/# END EMBEDDED CODEX FUNCTIONS/d' "$rcfile"; then
            err "Failed to remove existing functions from $rcfile"
            return 1
          fi
          ;;
      esac
    fi
  fi

  # Add new functions (fresh or after removal)
  if ! generate_functions >> "$rcfile"; then
    err "Failed to write functions to $rcfile"
    return 1
  fi
  ok "Installed embedded functions"

  echo
  info "Installation complete! Next steps:"
  ce "  1. Run: source \"$rcfile\""
  ce "  2. Test: codex-status"
  ce "  3. Try: bear-test"
}

# ─────────────────────────────── Uninstall ───────────────────────────────

uninstall_functions() {
  local rcfile
  rcfile="$(detect_shell_rc)"

  if [[ -f "$rcfile" ]] && grep -q "# BEGIN EMBEDDED CODEX FUNCTIONS" "$rcfile" 2>/dev/null; then
    local do_backup
    do_backup="$(ask_yes_no "Create a backup before uninstalling?" "Y")"
    if [[ "$do_backup" == "Y" ]]; then
      local default_dir
      default_dir="$(dirname "$rcfile")"
      local backup_dir
      read -r -p "Enter backup directory [${default_dir}]: " backup_dir
      backup_dir="${backup_dir:-$default_dir}"
      mkdir -p "$backup_dir"
      local backup_file="${backup_dir}/$(basename "$rcfile").backup.$(date +%Y%m%d-%H%M%S)"
      cp "$rcfile" "$backup_file"
      ok "Backup created at $backup_file"
    else
      warn "No backup created"
    fi

    if ! safe_sed_inplace '/# BEGIN EMBEDDED CODEX FUNCTIONS/,/# END EMBEDDED CODEX FUNCTIONS/d' "$rcfile"; then
      err "Failed to remove embedded functions from $rcfile"
      return 1
    fi
    ok "Removed embedded functions from $rcfile"
    info "Run: source \"$rcfile\" to reload your shell"
  else
    warn "No embedded functions found in $rcfile"
  fi
}

# ─────────────────────────────── Status Check ───────────────────────────────
check_status() {
  local rcfile
  rcfile="$(detect_shell_rc)"

  sep
  ce "Embedded Profile Functions Status"
  sep

  if [[ -f "$rcfile" ]] && grep -q "# BEGIN EMBEDDED CODEX FUNCTIONS" "$rcfile" 2>/dev/null; then
    ok "Embedded functions installed in $rcfile"

    local version_line
    version_line="$(grep "# Generated:" "$rcfile" 2>/dev/null || echo "Unknown version")"
    ce "  $version_line"

    local tiers_line
    tiers_line="$(grep "# Tiers:" "$rcfile" 2>/dev/null || echo "Unknown tiers")"
    ce "  $tiers_line"

    local model_line
    model_line="$(grep "# Model:" "$rcfile" 2>/dev/null || echo "Unknown model")"
    ce "  $model_line"
  else
    warn "No embedded functions found"
  fi

  if declare -f kiro >/dev/null 2>&1; then
    ok "Functions loaded in current session"
  else
    warn "Functions not loaded (run: source \"$rcfile\")"
  fi

  if command -v codex >/dev/null 2>&1; then
    ok "Codex CLI available: $(command -v codex)"
    ce "  Version: $(codex --version 2>/dev/null || echo 'unknown')"
  else
    err "Codex CLI not found"
  fi
}

# ─────────────────────────────── Main ───────────────────────────────
main() {
  if [[ $DO_VERSION -eq 1 ]]; then
    echo "Enhanced Embedded Profile Functions v${VERSION}"
    exit 0
  fi

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

    select_options_interactive
    select_tiers_interactive
  else
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
  ce "  Default File Opener: $FILE_OPENER (runtime override via CODEX_FILE_OPENER)"
  ce "  Bear Web Search default (CODEX_WEB_SEARCH): $CODEX_WEB_SEARCH"
  ce "  Quiet: $QUIET_MODE"
  ce "  Shell: $(detect_shell_rc)"
  sep

  if [[ $INTERACTIVE -eq 1 && "$(ask_yes_no "Proceed with installation?" "Y")" == "N" ]]; then
    ce "Installation cancelled"
    exit 0
  fi

  install_functions
}

main "$@"

