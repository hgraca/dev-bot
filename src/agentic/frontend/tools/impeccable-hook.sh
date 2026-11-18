#!/usr/bin/env bash
# =============================================================================
# src/agentic/frontend/tools/impeccable-hook.sh
# Run the Impeccable design detector over one file the agent just edited.
#
# Wired from ../hooks.json on the `file.edited` event, so both harness adapters
# dispatch it: opencode's on-hooks plugin and claudecode's PostToolUse(Edit|Write).
# Findings go to stdout, which the dispatcher routes to .agents/logs/impeccable.log.
#
# Why dev-bot dispatches this instead of `impeccable hooks on` installing a
# provider manifest (verified against impeccable 0.1.25):
#   - the provider list is Claude Code, Codex, Cursor, Copilot, Grok and Gemini
#     — no opencode, which is this toolkit's primary harness;
#   - it locates the project skill at .claude/skills, .cursor/skills, .codex/…
#     dev-bot links skills into <devbot_dir>/skills and flattens only SKILL.md
#     into .claude/skills, so in an opencode project the install reports "No
#     design harness is wired";
#   - its ".agents" provider is Codex's repo-skills folder, so in a dev-bot
#     project `hooks on` writes .codex/hooks.json — a manifest for a harness the
#     project does not run.
# The module therefore owns the dispatch, and .impeccable/config.json stays the
# single switch both the CLI (`impeccable hooks on|off|status`) and this hook read.
#
# Gates, all of which must pass before the engine runs:
#   1. this shell did not set IMPECCABLE_HOOK_DISABLED  (upstream's one-shot switch)
#   2. the project config enables the hook               (.impeccable/config.json)
#   3. a launcher resolves (skill linked, or the vendor clone)
#
# On consent: dev-bot never writes .impeccable/config.local.json. That file is
# the upstream manifest installer's per-machine record, and dev-bot does not
# install a manifest — module enablement plus a committed config.json is the
# project's opt-in, and `impeccable hooks off` (or deleting the config) is the
# opt-out. The file is gitignored anyway, so a developer who does run the
# upstream installer keeps their consent out of the repository.
#
# Usage: impeccable-hook.sh <project-root> <file>
# =============================================================================

set -uo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../functions.sh
source "${MODULE_DIR}/functions.sh"

# The reader lives beside this module, not under DEV_BOT_ROOT: tests point
# DEV_BOT_ROOT at a fixture, which would read nothing (same reason
# _devbot_get_config resolves it from its own location).
SHARED_DIR="$(cd "${MODULE_DIR}/../../_shared" && pwd)"

PROJECT_ROOT="${1:-}"
FILE="${2:-}"
[[ -n "${PROJECT_ROOT}" && -n "${FILE}" ]] || {
  echo "usage: impeccable-hook.sh <project-root> <file>" >&2
  exit 0
}
[[ -d "${PROJECT_ROOT}" ]] || exit 0

# ── Gate 1: upstream's one-shot switch ───────────────────────────────────────
case "${IMPECCABLE_HOOK_DISABLED:-}" in
  "" | "0" | "false") ;;
  *) exit 0 ;;
esac

CONFIG_DIR="${PROJECT_ROOT}/.impeccable"
CONFIG="${CONFIG_DIR}/config.json"

# _config_value <file> <key...> — a scalar from a JSONC config, empty when the
# file or key is absent. Booleans print as true/false (read_jsonc.py contract).
_config_value() {
  local file="$1"
  shift
  [[ -f "${file}" ]] || return 0
  python3 "${SHARED_DIR}/read_jsonc.py" "${file}" "$@" 2>/dev/null || true
}

# ── Gate 2: the project's switch ─────────────────────────────────────────────
# Absent config = the project never opted in (module off, or the file deleted).
[[ -f "${CONFIG}" ]] || exit 0
[[ "$(_config_value "${CONFIG}" hook enabled)" == "true" ]] || exit 0

# ── Gate 3: a launcher to run ────────────────────────────────────────────────
# The linked skill first (that is the copy the agent loads), then the vendor
# clone, for a project whose link was pruned or whose module was just enabled.
#
# devbot_dir is project config, so it is checked before it is joined onto a path
# and executed: an absolute value or a `..` escape would aim the launcher at any
# script on the machine. The same predicate guards it elsewhere
# (_devbot_is_plain_relative_path), and an unusable value falls back to the
# vendor clone rather than the project's tree.
DEV_BOT_DIR="$(_devbot_get_project_dir "${PROJECT_ROOT}")"
if ! _devbot_is_plain_relative_path "${DEV_BOT_DIR}"; then
  echo "impeccable: ignoring devbot_dir '${DEV_BOT_DIR}' — it is not a plain relative path; using the vendor launcher"
  DEV_BOT_DIR=""
fi
LAUNCHER=""
if [[ -n "${DEV_BOT_DIR}" ]]; then
  LAUNCHER="${PROJECT_ROOT}/${DEV_BOT_DIR}/skills/impeccable/scripts/impeccable"
fi
if [[ -z "${LAUNCHER}" || ! -f "${LAUNCHER}" ]]; then
  LAUNCHER="${DEV_BOT_ROOT}/vendor/pbakaus/impeccable/.agent/skills/impeccable/scripts/impeccable"
fi
if [[ ! -f "${LAUNCHER}" ]]; then
  echo "impeccable: no launcher found — the impeccable skill is not linked under ${DEV_BOT_DIR}/skills/; skipping the detector run"
  exit 0
fi

[[ -f "${FILE}" ]] || exit 0

# ── Run ──────────────────────────────────────────────────────────────────────
# From the project root: the engine resolves .impeccable/config.json, DESIGN.md
# and the inline-ignore rules relative to its working directory.
output="$(cd "${PROJECT_ROOT}" && bash "${LAUNCHER}" detect "${FILE}" 2>&1)"
status=$?

# A clean file is silent — the dispatcher records a marker for the run. Any
# other status keeps its output: 2 is "anti-patterns found", and everything
# else is a launcher/engine problem worth reading in the log.
if [[ -z "${output}" ]] || [[ ${status} -eq 0 ]]; then
  exit 0
fi

# ── Bound the log entry (hook.limits in .impeccable/config.json) ─────────────
# `impeccable hooks on` writes these limits for its own hook mode; a manual
# `detect` run ignores them, so the wrapper applies them here rather than
# letting one noisy file write an unbounded entry. With a limit configured the
# entry starts at the first finding: the engine's two-line "regex matching only,
# findings are an undercount" preamble would otherwise eat an aggressive budget
# and leave the findings — the point of the entry — truncated away.
max_findings="$(_config_value "${CONFIG}" hook limits maxFindings)"
max_chars="$(_config_value "${CONFIG}" hook limits maxChars)"

if [[ "${max_findings}" =~ ^[0-9]+$ ]] || [[ "${max_chars}" =~ ^[0-9]+$ ]]; then
  output="$(printf '%s\n' "${output}" | awk '
    /^[[:space:]]*line [0-9]+: \[/ { started = 1 }
    started { print }
  ')"
fi

if [[ "${max_findings}" =~ ^[0-9]+$ ]] && [[ "${max_findings}" -gt 0 ]]; then
  output="$(printf '%s\n' "${output}" | awk -v max="${max_findings}" '
    BEGIN { keep = 1; n = 0; dropped = 0 }
    /^[[:space:]]*line [0-9]+: \[/ {
      n++
      keep = (n <= max)
      if (!keep) dropped++
    }
    keep { print }
    END {
      if (dropped > 0) printf "… %d more finding(s) not shown (hook.limits.maxFindings=%d)\n", dropped, max
    }
  ')"
fi

if [[ "${max_chars}" =~ ^[0-9]+$ ]] && [[ "${max_chars}" -gt 0 ]] && [[ ${#output} -gt ${max_chars} ]]; then
  output="${output:0:${max_chars}}"$'\n'"… output truncated at ${max_chars} characters (hook.limits.maxChars)"
fi

printf '%s\n' "${output}"
if [[ ${status} -ne 2 ]]; then
  echo "impeccable: detector exited ${status}"
fi

# A finding is not a hook failure: exit 0 so the run is not reported as broken.
exit 0
