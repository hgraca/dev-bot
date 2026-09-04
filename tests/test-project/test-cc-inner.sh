#!/usr/bin/env bash
# =============================================================================
# test-cc-inner.sh — runs INSIDE the devbot-test container, invoked by the
# test-cc.sh launcher. Provisions prereqs, fetches the Claude desktop deb,
# re-inits devbot, runs the devbot-audit prompt, then drops to an interactive
# shell so you can keep working in the same container.
# =============================================================================
set -euo pipefail
cd /app

# Never prompt mid-test (e.g. the harness default-agent question) — the run
# must not block waiting for input.
export SKIP_CONFIRM=1
# qmd embedding can be slow on CPU — give it a generous bound.
export QMD_EMBED_TIMEOUT=300

# Use a SHARED qmd SQLite index for the devbot-test runs, living under the
# host-mounted qmd cache (~/.cache/qmd is mounted rw into every container), so
# parallel cc + oc runs index the ~600-doc global store ONCE, not once per
# container. The llama-heavy embed is serialized by qmd/init.sh's cross-process
# lock (.llama.lock in the same cache) — see qmd/init.sh. The host's REAL index
# (~/.cache/qmd/index.sqlite) is still never touched; this is a dedicated
# devbot-test database. Override with QMD_TEST_INDEX_PATH.
export INDEX_PATH="${QMD_TEST_INDEX_PATH:-$HOME/.cache/qmd/devbot-test/index.sqlite}"
mkdir -p "$(dirname "${INDEX_PATH}")"

# ── Duration capture ──────────────────────────────────────────────────────────
# Phase timings are collected into PHASES ("name:seconds") and printed (and
# saved to .agents/logs/test-durations.log) when the test flow reaches the
# interactive shell — so container startup cost is visible on every run.
PHASES=()
PHASE_START="$SECONDS"
_phase() { # _phase <name> — record the elapsed time of the just-finished phase
  local name="$1"
  PHASES+=("${name}:$(( SECONDS - PHASE_START ))")
  PHASE_START="$SECONDS"
}
_show_durations() {
  echo
  echo "=== Test phase durations ==="
  local total=0 entry name dur
  for entry in "${PHASES[@]}"; do
    name="${entry%%:*}"
    dur="${entry##*:}"
    printf '  %-24s %4ds\n' "${name}" "${dur}"
    total=$(( total + dur ))
  done
  printf '  %-24s %4ds\n' "TOTAL" "${total}"
  # .agents/logs is wiped by test-reinit.sh and recreated lazily only when a
  # harness session runs (cc recreates it via the audit, but not if it fails) —
  # ensure it exists first.
  mkdir -p /app/.agents/logs 2>/dev/null || true
  {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] test phase durations:"
    for entry in "${PHASES[@]}"; do
      printf '  %-24s %4ds\n' "${entry%%:*}" "${entry##*:}"
    done
    printf '  %-24s %4ds\n' "TOTAL" "${total}"
  } >> /app/.agents/logs/test-durations.log 2>/dev/null || true
}

# Ensure the project config targets the claudecode harness only.
set_harness() {
  python3 - <<'PY'
import json, sys
path = "/app/.devbot.project.jsonc"
try:
    with open(path) as f:
        d = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    d = {}
d["harness"] = "claudecode"
d.setdefault("modules", {})["opencode"] = False
d.setdefault("modules", {})["claudecode"] = True
with open(path, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
PY
}
set_harness
_phase "harness config"

# Prereqs (baked into the image; idempotent — sudo is NOPASSWD for this user).
sudo apt-get update >/dev/null
sudo apt-get install -y --no-install-recommends curl ca-certificates git openssh-client python3 >/dev/null
_phase "apt prereqs"

# The claude CLI is baked into the image (global npm package) — no download
# needed here.

# Make /app a real git repo for the duration of the test so git-dependent
# features work (git-report, branch-aware codebase-index) and git discovery
# doesn't emit "fatal: not a git repository" noise at the mount boundary.
# A stale .git from an aborted run is dropped first; the repo is removed on
# exit (see the EXIT trap at the end) so the host tree stays untouched.
if [ -e /app/.git ]; then rm -rf /app/.git; fi
git -C /app init -q
git -C /app config user.email devbot-test@example.com
git -C /app config user.name "devbot-test"
git -C /app config commit.gpgsign false
git -C /app add -A
git -C /app commit -q -m "test fixture snapshot"
echo "test git repo created in /app (removed on exit)"
_phase "git repo"

# (Re)init — handles the devbot install-if-missing + wiring. The install line
# uses the branch passed by the launcher (DEV_BOT_TEST_BRANCH, default main).
export DEV_BOT_TEST_BRANCH="${DEV_BOT_TEST_BRANCH:-main}"
. ./test-reinit.sh
_phase "reinit (install + wiring)"

# Grant the claudecode state dir through opencode's external_directory
# permission (the agent audits the harness itself). Merges; no-ops when
# opencode.jsonc is absent in a claudecode-only flow.
python3 "${HOME}/.local/share/dev-bot/src/_shared/upsert_opencode_permission.py" \
  "${PWD}/opencode.jsonc" "${HOME}/.claude/**" 2>/dev/null || true
_phase "claudecode grant"

# ── Agent audit — headless (opt-in) or manual ─────────────────────────────────
# Default (no --headless on the launcher): skip the audit entirely and drop to
# an interactive shell so you can run /devbot:audit manually in the harness.
# With --headless (DEVBOT_TEST_HEADLESS=1): run /devbot:audit through claude -p.
# That is the LONG phase (5-25 min depending on model). Output streams live AND
# is tee'd to .agents/logs/devbot-audit-run.log; a heartbeat prints every 60 s
# so a long run is visibly alive. Pick a fast model with
# DEVBOT_TEST_CLAUDE_MODEL (e.g. haiku).
if [[ "${DEVBOT_TEST_HEADLESS:-0}" == "1" ]]; then
  echo
  echo "▶ Running headless devbot audit (/devbot:audit)..."
  echo "  (streaming below; tee'd to .agents/logs/devbot-audit-run.log)"
  echo
  mkdir -p /app/.agents/logs 2>/dev/null || true
  AUDIT_START=$(date +%s)
  ( while :; do sleep 60; echo "  ⏱ audit still running ($(( $(date +%s) - AUDIT_START ))s)…"; done ) & AUDIT_HB=$!
  set +e
  if [[ -n "${DEVBOT_TEST_CLAUDE_MODEL:-}" ]]; then
    devbot -p --model "${DEVBOT_TEST_CLAUDE_MODEL}" "/devbot:audit" 2>&1 \
      | tee /app/.agents/logs/devbot-audit-run.log
  else
    devbot -p "/devbot:audit" 2>&1 | tee /app/.agents/logs/devbot-audit-run.log
  fi
  AUDIT_RC=${PIPESTATUS[0]}
  set -e
  kill "${AUDIT_HB}" 2>/dev/null || true
  wait "${AUDIT_HB}" 2>/dev/null || true
  _phase "agent audit"
  echo
  if [[ ${AUDIT_RC} -ne 0 ]]; then
    echo "WARN: devbot audit run failed (exit ${AUDIT_RC}) — tail of devbot-audit-run.log:"
    tail -5 /app/.agents/logs/devbot-audit-run.log 2>/dev/null | sed 's/^/  /'
  else
    # The audit must have written a report inside the isolated run; surface it.
    audit_report="$(find /app/.agents/memory/thinking -name 'devbot-audit-*.md' 2>/dev/null | sort | tail -1 || true)"
    if [[ -n "${audit_report}" ]]; then
      echo "✔ audit report written: ${audit_report}"
    else
      echo "WARN: devbot audit exited 0 but wrote NO devbot-audit-*.md report — see devbot-audit-run.log"
    fi
  fi
else
  echo "(headless audit skipped — run /devbot:audit manually in the harness below)"
fi

# Remove the test git repo when the container exits so the host mount
# (/app = this run's isolated copy) stays a plain directory. NOTE: not `exec` —
# the EXIT trap must fire after the interactive shell ends.
cleanup_test_repo() {
  if [ -e /app/.git ]; then
    rm -rf /app/.git
    echo "(removed test git repo from /app)"
  fi

  # Stage the claudecode harness logs into /app so the host launcher can sync
  # them back after the container is removed (--rm). Claude Code's per-server
  # MCP logs live under ~/.cache/claude-cli-nodejs/ INSIDE the container — not
  # on any host mount — so without this copy they vanish at container exit.
  # The launcher's sync_run_outputs() collects them under
  # .agents/logs/<report-id>/harness/ on the host.
  local claude_log_dir="$HOME/.cache/claude-cli-nodejs"
  if [ -d "${claude_log_dir}" ]; then
    mkdir -p /app/.agents/logs/harness
    cp -R "${claude_log_dir}/." /app/.agents/logs/harness/ 2>/dev/null || true
    echo "(staged claude harness logs to /app/.agents/logs/harness)"
  fi
}
trap cleanup_test_repo EXIT

_show_durations

# Non-interactive mode (DEVBOT_TEST_NONINTERACTIVE=1, forwarded by the
# launcher): finish the test and exit cleanly instead of parking at bash -i —
# the EXIT trap stages the harness logs and the host launcher syncs the audit
# report + logs back to the fixture. For automation/CI.
if [[ "${DEVBOT_TEST_NONINTERACTIVE:-0}" == "1" ]]; then
  echo "=== Test complete (non-interactive) — exiting ==="
  exit 0
fi

# Only drop into an interactive shell when stdin really is a tty — otherwise a
# `bash -i` with no usable stdin looks like a hang where typing does nothing.
if [[ -t 0 ]]; then
  echo
  echo "=== Test done — interactive shell (uid $(id -u)). Run 'exit' to leave. ==="
  bash -i
else
  echo "=== Test complete — no tty attached, exiting cleanly ==="
  exit 0
fi
