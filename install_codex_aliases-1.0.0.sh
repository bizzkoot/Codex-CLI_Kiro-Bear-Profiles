#!/usr/bin/env bash
set -euo pipefail

# Ensure running under bash (not plain sh/zsh)
if [ -z "${BASH_VERSION:-}" ]; then
  echo "Please run with bash: bash $0" >&2
  exit 1
fi


VERSION="1.0.0"

# ───────────────────────── helpers ─────────────────────────
ce(){ printf "%s\n" "$*" >&2; }
info(){ ce "👉 $*"; }
ok(){ ce "✅ $*"; }
warn(){ ce "⚠️  $*"; }
err(){ ce "❌ $*"; }
sep(){ ce "────────────────────────────────────────────────────"; }

usage() {
  cat <<'EOF'
install_codex_aliases.sh  v1.0.0  (interactive & standalone, 4-tier model support)

Usage (non-interactive):
  install_codex_aliases.sh --fresh [--force]
  install_codex_aliases.sh --repo PATH [--force]
  install_codex_aliases.sh --fresh --repo PATH [--force]
  install_codex_aliases.sh -h | --help

Environment overrides (non-interactive only):
  CODEX_MIN_MODEL=gpt-5-minimal
  CODEX_LOW_MODEL=gpt-5-low
  CODEX_MID_MODEL=gpt-5-medium
  CODEX_HIGH_MODEL=gpt-5-high
  CODEX_TIERS=min,low,mid,high   # which tiers to install (subset, comma-separated)

If you run with NO FLAGS, the script will ask you questions interactively,
including which model tiers (min/low/mid/high) you want and their exact IDs.

Options:
  --fresh        Global setup:
                   • ensures ~/.codex/config.toml profiles for selected tiers:
                       [kiro_*], [bear_*] per tier
                   • installs shell functions for each tier:
                       /kiro-<tier>, /bear-<tier>, plus /kiro and /bear default to 'mid'
  --repo PATH    Install or update playbooks at PATH/codex/{kiro.md,bear.md}
  --force        Overwrite conflicting entries without prompting
  -h, --help     Show this help
EOF
}

# ───────────────────────── defaults ─────────────────────────
MIN_MODEL="${CODEX_MIN_MODEL:-gpt-5-minimal}"
LOW_MODEL="${CODEX_LOW_MODEL:-gpt-5-low}"
MID_MODEL="${CODEX_MID_MODEL:-gpt-5-medium}"
HIGH_MODEL="${CODEX_HIGH_MODEL:-gpt-5-high}"
TIERS_CSV="${CODEX_TIERS:-}"

# ───────────────────────── args ─────────────────────────
FRESH=0
REPO_PATH=""
FORCE=0
INTERACTIVE=0

if [[ $# -eq 0 ]]; then
  INTERACTIVE=1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fresh) FRESH=1; shift ;;
    --repo) REPO_PATH="${2:-}"; shift 2 ;;
    --force) FORCE=1; shift ;;
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

# ───────────────────────── profiles
# Normalize a user-entered path: strip quotes, expand ~, and resolve to absolute if possible
normalize_path() {
  local p="$1"
  case "$p" in
    \"*\" ) p="${p%\"}"; p="${p#\"}";;
    \'*\' ) p="${p%\'}"; p="${p#\'}";;
  esac
  case "$p" in
    ~/*) p="${HOME}/${p#~/}";;
    "~" ) p="${HOME}";;
  esac
  if [ -d "$p" ]; then
    (cd "$p" && pwd)
  else
    printf "%s" "$p"
  fi
}
# ───────────────────────── profiles ─────────────────────────
ensure_profiles_for_tier() {
  local tier="$1"; shift
  local model="$1"; shift
  local cfg="$1"; shift
  local changed=0

  add_or_update_profile() {
    local name="$1" ; shift
    local model="$1" ; shift
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
prompt_files = ["codex/${name%%_*}.md"]
model = "${model}"
EOF
        changed=1
      else
        ok "Profile [${name}] already present (use --force to overwrite)"
      fi
    else
      cat >>"$cfg" <<EOF

[profiles.${name}]
prompt_files = ["codex/${name%%_*}.md"]
model = "${model}"
EOF
      ok "Added [profiles.${name}]"
      changed=1
    fi
  }

  add_or_update_profile "kiro_${tier}" "$model"
  add_or_update_profile "bear_${tier}" "$model"

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
  ensure_profiles_for_tier "mid" "$MID_MODEL" "$cfg" && changed_any=1

  if [[ " ${SELECTED_TIERS[*]} " == *" min "* ]]; then
    ensure_profiles_for_tier "min" "$MIN_MODEL" "$cfg" && changed_any=1
  fi
  if [[ " ${SELECTED_TIERS[*]} " == *" low "* ]]; then
    ensure_profiles_for_tier "low" "$LOW_MODEL" "$cfg" && changed_any=1
  fi
  if [[ " ${SELECTED_TIERS[*]} " == *" high "* ]]; then
    ensure_profiles_for_tier "high" "$HIGH_MODEL" "$cfg" && changed_any=1
  fi

  if [[ $changed_any -eq 0 ]]; then
    info "No changes to $cfg (profiles already configured)"
  fi
}

# ───────────────────────── shell functions ─────────────────────────
ensure_shell_functions() {
  local rcfile; rcfile="$(detect_shell_rc)"
  info "Using shell rc: $rcfile"
  [[ -f "$rcfile" ]] || : > "$rcfile"
  cp "$rcfile" "${rcfile}.bak.$(date +%Y%m%d-%H%M%S)"

  add_or_update_func() {
    local name="$1"; shift
    local body="$1"; shift
    local escaped_body
    escaped_body="$(printf "%s" "$body" | sed -e 's/[\/&]/\\&/g')"

    if grep -qE "^${name}\(\)\s*\{" "$rcfile"; then
      if [[ "$FORCE" -eq 1 ]]; then
        info "Updating existing function: $name (force)"
        sed -E -e "/^${name}\(\)\s*\{/,/^\}/c\
$escaped_body
" "$rcfile" > "${rcfile}.tmp"
        mv "${rcfile}.tmp" "$rcfile"
      else
        ok "Function $name already present (use --force to overwrite)"
      fi
    else
      info "Adding function: $name"
      printf "\n%s\n" "$body" >> "$rcfile"
    fi
  }

  # Base aliases map to 'mid'
  add_or_update_func "/kiro" '/kiro() { codex --profile kiro_mid "$@"; }'
  add_or_update_func "/bear" '/bear() { codex --profile bear_mid "$@"; }'

  # Tier helpers
  if [[ " ${SELECTED_TIERS[*]} " == *" min "* ]]; then
    add_or_update_func "/kiro-min" '/kiro-min() { codex --profile kiro_min "$@"; }'
    add_or_update_func "/bear-min" '/bear-min() { codex --profile bear_min "$@"; }'
  fi
  if [[ " ${SELECTED_TIERS[*]} " == *" low "* ]]; then
    add_or_update_func "/kiro-low" '/kiro-low() { codex --profile kiro_low "$@"; }'
    add_or_update_func "/bear-low" '/bear-low() { codex --profile bear_low "$@"; }'
  fi
  if [[ " ${SELECTED_TIERS[*]} " == *" mid "* ]]; then
    add_or_update_func "/kiro-mid" '/kiro-mid() { codex --profile kiro_mid "$@"; }'
    add_or_update_func "/bear-mid" '/bear-mid() { codex --profile bear_mid "$@"; }'
  fi
  if [[ " ${SELECTED_TIERS[*]} " == *" high "* ]]; then
    add_or_update_func "/kiro-high" '/kiro-high() { codex --profile kiro_high "$@"; }'
    add_or_update_func "/bear-high" '/bear-high() { codex --profile bear_high "$@"; }'
  fi

  ok "Functions installed in $rcfile"
  ce "To load them now, run: source \"$rcfile\""
}

# ───────────────────────── playbooks ─────────────────────────
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
# Kiro (Codex CLI) — Traceable Agentic Development (TAD) with Strict 3‑Gate Workflow

**Runtime:** OpenAI Codex CLI (profile-based).  
**Goal:** Produce `requirements.md` → `design.md` → `tasks.md` **in order**, with **preview → approval → write** gates at each step.  
**Safety:** During *thinking* and *preview* phases, **do not write files** or run commands.

> This playbook is adapted from the original Kiro TAD spec and tightened for Codex CLI to prevent skipping steps and to ensure user approvals are collected before any file is written.

---

## Phase 0 — Mandatory Thinking (🛑 No Files, No Code Execution)

Complete this section **before** any document generation. If any item is uncertain, ask 3–5 focused clarification questions and wait.

- **0.A Problem framing (1–2 sentences):** objective, primary users/value, non‑goals.
- **0.B Assumptions (≤5, with confidence %).**
- **0.C Constraints:** tech, org, time, compliance.
- **0.D Options (≥2):** A vs B with pros/cons → **selection + rationale**.
- **0.E Test strategy sketch:** how each EARS AC group will be validated.
- **0.F Go/No‑Go:** proceed only if every AC group has ≥1 validation and all critical ambiguities are cleared.

**Hard rules in Phase 0:**  
- Output **text only** (no file writes).  
- If something is unclear, stop and ask concise questions.

---

## Phase 1 — Controlled Generation (Three Gates)

For each artifact, follow **Preview → Approval → Write**. Never skip or reorder.

> Use `{feature-name-kebab}` as the directory slug under `specs/`.

### Gate 1 — `requirements.md` (Semantic Anchor)

**A. PREVIEW (print only):**  
Output a single fenced block labeled `PREVIEW requirements.md` that contains the complete file content to review, **including examples**. Do **not** write the file yet.

The content MUST include these sections and examples:
````markdown
# Requirements: [Feature Name]
## Meta-Context
- Feature UUID: FEAT-{8-char-hash}
- Parent Context: [AGENTS.md links]
- Dependency Graph: [Auto-detected]

## Functional Requirements
### REQ-{UUID}-001: [Name]
Intent Vector: {AI semantic summary}
As a [User] I want [Goal] So that [Benefit]
Business Value: {1-10} | Complexity: {XS/S/M/L/XL}

Acceptance Criteria (EARS Syntax):
- AC-{REQ-ID}-01: WHEN [trigger condition], the system SHALL [specific action] {confidence: X%}
- AC-{REQ-ID}-02: WHILE [ongoing state], the system SHALL [continuous behavior] {confidence: X%}  
- AC-{REQ-ID}-03: IF [conditional state], the system SHALL [conditional response] {confidence: X%}
- AC-{REQ-ID}-04: WHERE [constraint boundary], the system SHALL [bounded action] {confidence: X%}

EARS Examples:
- WHEN user submits valid login credentials, the system SHALL authenticate within 200ms
- WHILE user session is active, the system SHALL maintain authentication state  
- IF login attempts exceed 3 failures, the system SHALL temporarily lock the account for 15 minutes
- WHERE user lacks required permissions, the system SHALL display "Access Denied" message

Validation Hooks: {EARS-to-BDD testable assertions}
Risk Factors: {auto-identified}

## Non-functional Requirements (EARS Format)
- NFR-{UUID}-PERF-001: WHEN [operation trigger], the system SHALL [perform action] within [time constraint]
- NFR-{UUID}-SEC-001: WHERE [security context], the system SHALL [enforce protection] using [method]
- NFR-{UUID}-UX-001: WHILE [user interaction], the system SHALL [provide feedback] within [response time]
- NFR-{UUID}-SCALE-001: IF [load condition], the system SHALL [maintain performance] up to [capacity limit]

NFR Examples:
- WHEN user requests dashboard data, the system SHALL load results within 500ms
- WHERE sensitive data is accessed, the system SHALL require multi-factor authentication  
- WHILE form validation occurs, the system SHALL display real-time feedback within 100ms
- IF concurrent users exceed 1000, the system SHALL maintain 99% uptime with <2s response times

## Traceability Manifest
Upstream: [dependencies] | Downstream: [impact] | Coverage: [AI-calculated]
````

**B. APPROVAL prompt:**  
Ask the user to reply exactly with: `APPROVE REQUIREMENTS` to proceed, or `REVISE REQUIREMENTS: ...` with edits.

**C. WRITE (after explicit approval only):**  
On `APPROVE REQUIREMENTS`, write the file by outputting a fenced block labeled:
```
WRITE specs/{feature-name-kebab}/requirements.md
<the same approved content>
```
Then print: `OK: wrote specs/{feature-name-kebab}/requirements.md`

---

### Gate 2 — `design.md` (Architecture Mirror)

**A. PREVIEW (print only):**  
Output `PREVIEW design.md` with **complete content** (no writes yet). Must include ADRs, component contracts (EARS annotations), API matrix, data flow + traceability, and quality gates. Include the TypeScript interface example and the API table.

**B. APPROVAL prompt:**  
User replies `APPROVE DESIGN` or `REVISE DESIGN: ...`

**C. WRITE (after approval):**  
```
WRITE specs/{feature-name-kebab}/design.md
<approved content>
```
Then: `OK: wrote specs/{feature-name-kebab}/design.md`

---

### Gate 3 — `tasks.md` (Execution Blueprint)

**A. PREVIEW (print only):**  
Output `PREVIEW tasks.md` with full content including:
- Metadata (complexity, critical path, risk, timeline)
- Progress counters
- Phase breakdown with tasks (EARS DoD)
- Verification checklist (EARS/BBD/NFR mapping)

**B. APPROVAL prompt:**  
User replies `APPROVE TASKS` or `REVISE TASKS: ...`

**C. WRITE (after approval):**  
```
WRITE specs/{feature-name-kebab}/tasks.md
<approved content>
```
Then: `OK: wrote specs/{feature-name-kebab}/tasks.md`

---

## Phase 2 — After All Three Are Approved & Written

- Ask: “Shall I **start execution** based on `tasks.md`? Reply `START` to proceed or `PAUSE` to defer.”  
- On `START`: execute one task at a time, verifying against mapped AC IDs.  
- Never skip ahead without explicit user instruction.

---

## Internal Review Gate (Before Each Approval)

- Map every REQ-* → ≥1 task  
- Every EARS AC has a validation hook  
- NFRs measurable & linked to design choices  
- Rubric (0–3): Clarity, Correctness, Safety, Testability, Simplicity  
If any fail → **REVISE** and do **not** request approval.

---

## AGENTS.md Update Assessment (Post‑Generation)

After writing all three files, ask if `AGENTS.md` needs updates (stack changes, ADRs that shift direction, new domain concepts, new constraints). If yes, propose the exact deltas and ask for approval before writing.

---

## Compatibility Notes (Codex CLI)

- Profiles supply this playbook as context; **no Task()** APIs, and **no shell execution** is assumed.  
- File writes are simulated via the `WRITE <path>` fenced blocks so users (or tooling) can apply them safely.  
- Always wait for the exact approval tokens before any `WRITE` block.

KIRO_EOF
    ok "Wrote $kiro_dst"
  fi

  if [[ -f "$bear_dst" && "$FORCE" -ne 1 ]]; then
    if [[ ${INTERACTIVE:-0} -eq 1 ]]; then
      read -r -p "bear.md already exists. Overwrite? [y/N] " __ans || true
      case "${__ans:-N}" in y|Y) : ;; *) warn "Skipped: $bear_dst"; __skip_bear=1;; esac
    else
      warn "$bear_dst already exists; use --force to overwrite"; __skip_bear=1
    fi
  fi
  if [[ -z "${__skip_bear:-}" ]]; then
    cat > "$bear_dst" <<'BEAR_EOF'
# BEAR (Codex CLI) — Executor Agent with Thinking & Review Gates

**Runtime:** OpenAI Codex CLI (profile-based).  
**Purpose:** Implement tasks **only after** a deliberate plan is reviewed and approved.  
**Note:** Delegate by stepwise Author Mode after APPROVE; avoid Claude-specific Task(...) calls.

## Phase 0: Thinking-Only Mode (🛑 No Code or Commands)
Produce planning artifacts only. **Do not** output code fences or run commands in this phase.

### A. Plan Summary (≤8 bullets)
- Objective, constraints, touchpoints, success metric, non-goals.

### B. Risk Review (top 5)
- Each risk → mitigation & detection signal.

### C. Alternatives Considered
- Option A vs Option B (+ why chosen); note complexity/perf/testability impact.

### D. Tests-First Outline
- Smoke tests, AC coverage map, negative/edge cases, perf/SEC checks.

### E. EARS Alignment
- List AC IDs to validate first and how.

### F. Execution Mini-DAG
- Ordered steps mapped to your `tasks.md` with dependencies.

### G. Verdict
- **APPROVE** — proceed to Author Mode  
- **REVISE** — stop and list **Instructions to Revise**

**Gate:** If any AC lacks a validation step, or risks lack mitigations, set Verdict = **REVISE**.

---

## Author Mode (after APPROVE)
Work step-by-step with checks:
- Intent (→ REQ/AC/NFR)  
- Change (code/config)  
- Tests (what you run and why)  
- Result (brief)  
If any planned check fails → stop and return to Phase 0 to revise.

---

## Memory & Notes (Optional)
Store artifacts in `~/.codex/memory/[timestamp]/` to enable recall in future sessions.

BEAR_EOF
    ok "Wrote $bear_dst"
  fi

  ce "Try from your terminal (not inside Codex):"
  ce "  /kiro \"New Feature\"      # mid default"
  if [[ " ${SELECTED_TIERS[*]} " == *" min "* ]]; then ce "  /kiro-min \"New Feature\""; fi
  if [[ " ${SELECTED_TIERS[*]} " == *" low "* ]]; then ce "  /kiro-low \"New Feature\""; fi
  ce "  /kiro-mid \"New Feature\"   # mid explicit"
  if [[ " ${SELECTED_TIERS[*]} " == *" high "* ]]; then ce "  /kiro-high \"New Feature\""; fi
  ce "  /bear \"Task\"             # mid default"
  if [[ " ${SELECTED_TIERS[*]} " == *" min "* ]]; then ce "  /bear-min \"Task\""; fi
  if [[ " ${SELECTED_TIERS[*]} " == *" low "* ]]; then ce "  /bear-low \"Task\""; fi
  ce "  /bear-mid \"Task\"          # mid explicit"
  if [[ " ${SELECTED_TIERS[*]} " == *" high "* ]]; then ce "  /bear-high \"Task\""; fi
}

# ───────────────────────── interactive ─────────────────────────
ask_yes_no() {
  local prompt="$1"
  local default="${2:-N}" # Y or N
  local answer
  local hint="[y/N]"
  [[ "$default" == "Y" ]] && hint="[Y/n]"
  while true; do
    read -r -p "$prompt $hint " answer || true
    answer="${answer:-$default}"
    case "$answer" in
      Y|y) echo "Y"; return 0 ;;
      N|n) echo "N"; return 0 ;;
      *) ce "Please answer y or n." ;;
    esac
  done
}

read_with_default() {
  local prompt="$1"
  local default="$2"
  local value
  read -r -p "$prompt [$default]: " value || true
  echo "${value:-$default}"
}

parse_tiers_csv() {
  local csv="$1"
  local -a tiers=()
  IFS=',' read -r -a raw <<< "$csv"
  for t in "${raw[@]}"; do
    case "${t// /}" in
      1|min|minimal) tiers+=("min");;
      2|low)         tiers+=("low");;
      3|mid|medium)  tiers+=("mid");;
      4|high)        tiers+=("high");;
      "") ;;
      *) warn "Ignoring unknown tier: $t";;
    esac
  done
  printf "%s\n" "${tiers[@]}"
}

# ───────────────────────── run ─────────────────────────
check_codex

declare -a SELECTED_TIERS=()

if [[ $INTERACTIVE -eq 1 ]]; then
  sep
  ce "install_codex_aliases.sh  v$VERSION — interactive mode"
  sep

  ce "▌ Select model tiers to install (comma-separated):"
  ce "▌  1) min (gpt-5-minimal)"
  ce "▌  2) low (gpt-5-low)"
  ce "▌  3) mid (gpt-5-medium)  (recommended default)"
  ce "▌  4) high (gpt-5-high)"
  read -r -p "Enter choices [default: low,mid]: " tier_input || true
  tier_input="${tier_input:-low,mid}"
  SELECTED_TIERS=()
while IFS= read -r __tier; do
  SELECTED_TIERS+=("$__tier")
done < <(parse_tiers_csv "$tier_input")

  # Compute tiers to prompt for models: selected tiers + always "mid" (base alias)
  TIER_PROMPT=()
  # add selected tiers
  for t in "${SELECTED_TIERS[@]}"; do
    TIER_PROMPT+=("$t")
  done
  # ensure "mid" is included once
  need_mid=1
  for t in "${TIER_PROMPT[@]:-}"; do [ "$t" = "mid" ] && need_mid=0; done
  [ $need_mid -eq 1 ] && TIER_PROMPT+=("mid")

  if [[ "$(ask_yes_no 'Do you want to do a fresh GLOBAL setup (profiles + shell functions)?' 'Y')" == "Y" ]]; then
    # Prompt for model IDs only for needed tiers
    ce "▌ Enter model IDs for installed tiers (press Enter to accept defaults):"
    for tier in "${TIER_PROMPT[@]}"; do
      case "$tier" in
        min) read -r -p "  min model id [$MIN_MODEL]: " ans || true; MIN_MODEL="${ans:-$MIN_MODEL}";;
        low) read -r -p "  low model id [$LOW_MODEL]: " ans || true; LOW_MODEL="${ans:-$LOW_MODEL}";;
        mid) read -r -p "  mid model id [$MID_MODEL]: " ans || true; MID_MODEL="${ans:-$MID_MODEL}";;
        high) read -r -p "  high model id [$HIGH_MODEL]: " ans || true; HIGH_MODEL="${ans:-$HIGH_MODEL}";;
      esac
    done
    sep
    ce "Using (only tiers to be installed are prompted above):"
    ce "  min=${MIN_MODEL}   low=${LOW_MODEL}   mid=${MID_MODEL}   high=${HIGH_MODEL}"
    ce "  tiers=$(printf "%s," "${SELECTED_TIERS[@]}" | sed 's/,$//')"
    sep
    ensure_profiles
    ensure_shell_functions
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

# Non-interactive path
if [[ -z "$TIERS_CSV" ]]; then
  TIERS_CSV="low,mid"
fi
SELECTED_TIERS=()
while IFS= read -r __tier; do
  SELECTED_TIERS+=("$__tier")
done < <(parse_tiers_csv "$TIERS_CSV")

ensure_profiles
ensure_shell_functions

if [[ -n "${REPO_PATH:-}" ]]; then
  REPO_PATH="$(normalize_path "$REPO_PATH")"
  if [[ ! -d "$REPO_PATH" ]]; then
    err "Repo path not found: $REPO_PATH"
    exit 1
  fi
  write_playbooks_to_repo "$REPO_PATH"
  ok "Playbooks installed to: $REPO_PATH/codex"
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