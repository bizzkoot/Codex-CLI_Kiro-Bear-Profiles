#!/usr/bin/env bash
set -euo pipefail

# Ensure running under bash (not plain sh/zsh)
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Please run with bash: bash $0" >&2
  exit 1
fi

VERSION="1.0.3"
SCRIPT_NAME="install_codex_aliases-${VERSION}.sh"

# ───────────────────────── helpers ─────────────────────────
ce(){ printf "%s\n" "$*" >&2; }
info(){ ce "👉 $*"; }
ok(){ ce "✅ $*"; }
warn(){ ce "⚠️  $*"; }
err(){ ce "❌ $*"; }
sep(){ ce "────────────────────────────────────────────────────"; }

usage() {
  cat <<'EOF'
install_codex_aliases.sh  v1.0.3  (Codex CLI native, gpt-5 with tiered reasoning)

Usage (non-interactive):
  install_codex_aliases.sh --fresh [--force]
  install_codex_aliases.sh --repo PATH [--force]
  install_codex_aliases.sh --fresh --repo PATH [--force]
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

If you run with NO FLAGS, the script will ask you questions interactively,
including which reasoning tiers (min/low/mid/high) you want.

What this does (when --fresh or interactive YES):
  • Ensures ~/.codex/config.toml profiles for selected tiers:
      [profiles.kiro_*], [profiles.bear_*] with model=gpt-5 and model_reasoning_effort per tier
      prompt_files = ["codex/<role>.md", "~/.codex/playbooks/<role>.md"]  (repo-first, global fallback)
  • Installs shell alias/functions for each tier between BEGIN/END markers:
      /kiro-<tier>, /bear-<tier>, plus /kiro and /bear (default to 'mid')
  • Writes global playbooks to ~/.codex/playbooks/{kiro.md,bear.md}
  • (Optional) Writes repo playbooks at PATH/codex/{kiro.md,bear.md}

This 1.0.3 keeps Kiro/Bear separation but trims verbose “thinking steps”.
Kiro generates/updates requirements.md, design.md, tasks.md via short preview→approve→write loops.
Bear executes tasks incrementally with patch-ready diffs. Chain-of-thought is NOT printed.
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

INTERACTIVE=0
if [[ -t 0 && -t 1 ]]; then INTERACTIVE=1; fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fresh) DO_FRESH=1; shift ;;
    --repo) REPO_PATH_INPUT="${2:-}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --check) DO_CHECK=1; shift ;;
    --uninstall) DO_UNINSTALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown arg: $1"; usage; exit 2 ;;
  esac
done

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

# ───────────────────────── profiles (global config)
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

    if grep -q "^\[profiles\.${name}\]" "$cfg"; then
      if [[ "$FORCE" -eq 1 ]]; then
        info "Updating profile [$name] (force)"
        awk -v section="profiles.${name}" '
          BEGIN{skip=0}
          /^\[profiles\./{
            if ($0 ~ "\["section"\]"){ skip=1; next }
            if (skip==1){ skip=0 }
          }
          { if (skip==0) print }
        ' "$cfg" > "${cfg}.tmp"
        mv "${cfg}.tmp" "$cfg"
        cat >>"$cfg" <<EOF

[profiles.${name}]
prompt_files = ["${repo_prompt}", "${global_prompt}"]
model = "${CODEX_MODEL}"
model_reasoning_effort = "${effort}"
EOF
        changed=1
      else
        read -r -p "Profile [${name}] exists in $cfg. Overwrite? [y/N]: " ans
      case "$ans" in
        [Yy]*)
          info "Overwriting profile [${name}]"
          awk -v section="profiles.${name}" '
            BEGIN{skip=0}
            /^\[profiles\./{
              if ($0 ~ "\["section"\]"){ skip=1; next }
              if (skip==1){ skip=0 }
            }
            { if (skip==0) print }
          ' "$cfg" > "${cfg}.tmp"
          mv "${cfg}.tmp" "$cfg"
          cat >>"$cfg" <<EOF

[profiles.${name}]
prompt_files = ["${repo_prompt}", "${global_prompt}"]
model = "${CODEX_MODEL}"
model_reasoning_effort = "${effort}"
EOF
          changed=1
          ;;
        *) info "Keeping existing profile [${name}]";;
      esac
      fi
    else
      info "Adding profile [${name}]"
      cat >>"$cfg" <<EOF

[profiles.${name}]
prompt_files = ["${repo_prompt}", "${global_prompt}"]
model = "${CODEX_MODEL}"
model_reasoning_effort = "${effort}"
EOF
      ok "Added [profiles.${name}]"
      changed=1
    fi
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

# ───────────────────────── shell functions (BEGIN/END block) ─────────────────────────
install_shell_block() {
  local rcfile; rcfile="$(detect_shell_rc)"
  info "Using shell rc: $rcfile"
  [[ -f "$rcfile" ]] || : > "$rcfile"
  cp "$rcfile" "${rcfile}.bak.$(date +%Y%m%d-%H%M%S)"

  # Remove existing block (idempotent)
  if grep -q "# BEGIN CODEX ALIASES v1.0.3" "$rcfile" 2>/dev/null; then
    awk '/# BEGIN CODEX ALIASES v1.0.3/{flag=1} !flag{print} /# END CODEX ALIASES v1.0.3/{flag=0}' "$rcfile" > "${rcfile}.tmp"
    mv "${rcfile}.tmp" "$rcfile"
  fi

  cat >> "$rcfile" <<'EOF'
# BEGIN CODEX ALIASES v1.0.3
# Aliases call Codex profiles; profiles define repo-first prompt_files with a global fallback.

alias /codex-aliases='alias | grep -E "^/(kiro|bear)" | sort'

# Kiro (planning & artifacts)
/kiro()       { codex --profile kiro_mid  "$@"; }
/kiro-min()   { codex --profile kiro_min  "$@"; }
/kiro-low()   { codex --profile kiro_low  "$@"; }
/kiro-mid()   { codex --profile kiro_mid  "$@"; }
/kiro-high()  { codex --profile kiro_high "$@"; }

# Bear (implementation & diffs)
/bear()       { codex --profile bear_mid  "$@"; }
/bear-min()   { codex --profile bear_min  "$@"; }
/bear-low()   { codex --profile bear_low  "$@"; }
/bear-mid()   { codex --profile bear_mid  "$@"; }
/bear-high()  { codex --profile bear_high "$@"; }
# END CODEX ALIASES v1.0.3
EOF

  ok "Functions installed in $rcfile (between BEGIN/END markers)"
  ce "To load them now, run: source \"$rcfile\""
}

# ───────────────────────── playbooks (global + repo) ─────────────────────────
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
    cat > "$kiro_dst" <<'KIRO_EOF'
# Kiro (Codex CLI) — Lean Planning & Artifacts (No Chain-of-Thought)

**Runtime:** Codex CLI profile `kiro_*` (model: gpt-5, reasoning: tiered).  
**Goal:** Maintain `requirements.md`, `design.md`, `tasks.md` via short **preview → APPROVE/REVISE → write** loops.  
**Resumable:** On re-run, read existing files and propose diffs (concise).

## Behavior
- Be concise. Use internal reasoning; do **not** print thinking steps.
- Ask ≤2 clarifying questions only if you cannot proceed.
- Prefer EARS-style requirements and light traceability.
- When updating, show a **minimal diff** against existing file before writing.

## Flow
1) **Requirements PREVIEW** (bulleted): scope, constraints, acceptance criteria (IDs).  
   Wait for **APPROVE** or **REVISE**. If APPROVE → write `requirements.md`.
2) **Design PREVIEW** (bulleted): components, integration points, risks/mitigations.  
   Wait for **APPROVE** or **REVISE**. If APPROVE → write `design.md`.
3) **Tasks PREVIEW**: numbered, small, testable tasks, reference AC IDs.  
   Wait for **APPROVE** or **REVISE**. If APPROVE → write/merge `tasks.md`.

## Update Rules
- If files exist, READ them and propose **delta** sections with diffs.
- Keep previews ≤ ~200 lines. Avoid restating the whole codebase.
- After writing, suggest next action or handoff to **/bear**.
KIRO_EOF
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
    cat > "$bear_dst" <<'BEAR_EOF'
# Bear (Codex CLI) — Lean Executor (No Chain-of-Thought)

**Runtime:** Codex CLI profile `bear_*` (model: gpt-5, reasoning: tiered).  
**Purpose:** Implement tasks from `tasks.md` (or a provided task) with minimal patches and quick validation.

## Behavior
- Be concise. Do not print chain-of-thought.
- Start with a **micro-plan** (3–6 bullets). Reference `tasks.md` item IDs.
- Produce **patch-ready diffs** (unified) or exact file blocks. Small increments.
- Run/validate when appropriate; summarize results and propose the next step.

## Steps
1) **Micro-plan** + risks (very brief).  
2) **Apply patch** (diff or file block).  
3) **Run/validate** (if applicable); show short output.  
4) **Next step** or stop.

Tip: Prefer many small commits over a single large change.
BEAR_EOF
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
    cat > "$kiro_dst" <<'KIRO_EOF'
# Kiro (Codex CLI) — Lean Planning & Artifacts (No Chain-of-Thought)

See global playbook for full guidance. This repo copy is the **project-first** prompt.
(If absent, Codex falls back to ~/.codex/playbooks/kiro.md)

[Same behavior as global copy: previews, approvals, write, resumable updates.]
KIRO_EOF
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
    cat > "$bear_dst" <<'BEAR_EOF'
# Bear (Codex CLI) — Lean Executor (No Chain-of-Thought)

Repo-first prompt. Falls back to ~/.codex/playbooks/bear.md if missing.
[Same behavior as global copy: micro-plan → patch → validate → next step.]
BEAR_EOF
    ok "Wrote $bear_dst"
  fi
}

# ───────────────────────── interactive & main ─────────────────────────
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
  if [[ -z "${ans:-}" ]]; then
    TIERS_CSV="low,mid"
  else
    ans="${ans//1/min}"; ans="${ans//2/low}"; ans="${ans//3/mid}"; ans="${ans//4/high}"
    TIERS_CSV="$ans"
  fi
}

parse_tiers_csv() {
  local csv="${1:-}"; local -a out=()
  if [[ -z "$csv" ]]; then csv="low,mid"; fi
  IFS=',' read -r -a parts <<<"$csv"
  for t in "${parts[@]}"; do
    case "$t" in min|low|mid|high) out+=("$t");; *) warn "Ignoring unknown tier: $t" ;; esac
  done
  if [[ ${#out[@]} -eq 0 ]]; then out=(low mid); fi
  printf "%s\n" "${out[@]}"
}

uninstall_everything() {
  sep; info "Uninstalling aliases and playbooks (safe)"; sep
  # Remove playbooks
  rm -f "$KIRO_PB_GLOBAL" "$BEAR_PB_GLOBAL" || true
  ok "Removed global playbooks (if present)."

  # Remove shell alias block
  local rcfile; rcfile="$(detect_shell_rc)"
  if grep -q "# BEGIN CODEX ALIASES v1.0.3" "$rcfile" 2>/dev/null; then
    awk '/# BEGIN CODEX ALIASES v1.0.3/{flag=1} !flag{print} /# END CODEX ALIASES v1.0.3/{flag=0}' "$rcfile" > "${rcfile}.tmp"
    mv "${rcfile}.tmp" "$rcfile"
    ok "Removed alias block from $rcfile"
  else
    warn "Alias block not found in $rcfile"
  fi

  # Optionally remove profiles (commented for safety). Uncomment to enable hard cleanup.
  # local cfg="${HOME}/.codex/config.toml"
  # if [[ -f "$cfg" ]]; then
  #   for name in kiro_min kiro_low kiro_mid kiro_high bear_min bear_low bear_mid bear_high; do
  #     awk -v section="profiles.${name}" '
  #       BEGIN{skip=0}
  #       /^\[profiles\./{
  #         if ($0 ~ "\["section"\]"){ skip=1; next }
  #         if (skip==1){ skip=0 }
  #       }
  #       { if (skip==0) print }
  #     ' "$cfg" > "${cfg}.tmp" && mv "${cfg}.tmp" "$cfg"
  #   done
  #   ok "Removed profile sections from $cfg"
  # fi
}

main() {
  check_codex

  # Interactive if no flags
  if [[ $DO_CHECK -eq 0 && $DO_UNINSTALL -eq 0 && $DO_FRESH -eq 0 && -z "${REPO_PATH_INPUT:-}" && $INTERACTIVE -eq 1 ]]; then
    select_tiers_interactive
    SELECTED_TIERS=($(parse_tiers_csv "$TIERS_CSV"))

    if [[ "$(ask_yes_no 'Proceed with global setup (profiles + aliases + global playbooks)?' 'Y')" == "Y" ]]; then
      sep
      ce "Using model and reasoning per tier:"
      ce "  model=${CODEX_MODEL}"
      ce "  reasoning: min=${REASON_MIN} low=${REASON_LOW} mid=${REASON_MID} high=${REASON_HIGH}"
      ce "  tiers=$(printf "%s," "${SELECTED_TIERS[@]}" | sed 's/,$//')"
      sep
      ensure_profiles
      install_shell_block
      write_playbooks_global
      ok "Global setup complete."
    else
      info "Skipping global setup."
    fi

    if [[ "$(ask_yes_no 'Install or update the playbooks (kiro.md & bear.md) into a REPO now?' 'Y')" == "Y" ]]; then
      read -r -p "Enter repo path [default: current directory]: " REPO_PATH_INPUT || true
      REPO_PATH_INPUT="${REPO_PATH_INPUT:-$(pwd)}"
      REPO_PATH_INPUT="$(normalize_path "$REPO_PATH_INPUT")"
      if [[ -d "$REPO_PATH_INPUT" ]]; then
        write_playbooks_to_repo "$REPO_PATH_INPUT"
        ok "Playbooks installed to: $REPO_PATH_INPUT/codex"
      else
        err "Path does not exist: $REPO_PATH_INPUT"
        exit 1
      fi
    else
      info "Skipping repo playbook installation."
    fi

    sep
    ok "All done."
    ce "If you modified your shell rc, run: source \"$(detect_shell_rc)\""
    ce "Examples to run:"
    ce "  /kiro \"New Feature\"        # mid default"
    for t in "${SELECTED_TIERS[@]}"; do
      ce "  /kiro-${t} \"New Feature\""
    done
    ce "  /bear \"Task\"               # mid default"
    for t in "${SELECTED_TIERS[@]}"; do
      ce "  /bear-${t} \"Task\""
    done

    exit 0
  fi

  # Non-interactive flows
  if [[ $DO_UNINSTALL -eq 1 ]]; then
    uninstall_everything
    ok "Uninstall complete."
    exit 0
  fi

  # Parse tiers from env for non-interactive flows
  SELECTED_TIERS=($(parse_tiers_csv "$TIERS_CSV"))

  if [[ $DO_CHECK -eq 1 ]]; then
    sep
    ce "Codex CLI: $(command -v codex)"
    ce "Model: ${CODEX_MODEL}"
    ce "Reasoning (min/low/mid/high): ${REASON_MIN}/${REASON_LOW}/${REASON_MID}/${REASON_HIGH}"
    sep
    ce "Profiles & reasoning (from ~/.codex/config.toml, if present):"
    if [[ -f "$HOME/.codex/config.toml" ]]; then
      awk '/^\[profiles\./, /^$/' "$HOME/.codex/config.toml" >&2 || true
    else
      warn "No ~/.codex/config.toml found"
    fi
    sep
    local rcfile; rcfile="$(detect_shell_rc)"
    ce "Shell RC: $rcfile"
    if grep -q "# BEGIN CODEX ALIASES v1.0.3" "$rcfile" 2>/dev/null; then
      ok "Alias block present"
    else
      warn "Alias block not found (run --fresh to install)"
    fi
    sep
    ce "Aliases (may require 'source $rcfile'):"
    for a in /kiro /kiro-min /kiro-low /kiro-mid /kiro-high /bear /bear-min /bear-low /bear-mid /bear-high; do
      if alias "$a" >/dev/null 2>&1; then
        printf "  [ok] %s\n" "$a" >&2
      else
        printf "  [  ] %s\n" "$a" >&2
      fi
    done
    exit 0
  fi

  if [[ $DO_FRESH -eq 1 ]]; then
    sep
    ce "Using model and reasoning per tier:"
    ce "  model=${CODEX_MODEL}"
    ce "  reasoning: min=${REASON_MIN} low=${REASON_LOW} mid=${REASON_MID} high=${REASON_HIGH}"
    ce "  tiers=$(printf "%s," "${SELECTED_TIERS[@]}" | sed 's/,$//')"
    sep
    ensure_profiles
    install_shell_block
    write_playbooks_global
    ok "Global setup complete (non-interactive)."
  fi

  if [[ -n "${REPO_PATH_INPUT:-}" ]]; then
    REPO_PATH_INPUT="$(normalize_path "$REPO_PATH_INPUT")"
    [[ -d "$REPO_PATH_INPUT" ]] || { err "Path does not exist: $REPO_PATH_INPUT"; exit 1; }
    write_playbooks_to_repo "$REPO_PATH_INPUT"
    ok "Playbooks installed to: $REPO_PATH_INPUT/codex"
  fi

  sep
  ok "All done."
  ce "If you modified your shell rc, run: source \"$(detect_shell_rc)\""
  ce "Examples to run:"
  ce "  /kiro \"Draft requirements/design/tasks for Feature X (EARS style)\""
  ce "  /bear \"Implement task #3 from tasks.md; output minimal diff and run tests\""
}

main "$@"
