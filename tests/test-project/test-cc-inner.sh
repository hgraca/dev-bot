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

# Use an ISOLATED qmd SQLite index for the test, so the host's shared index
# (~/.cache/qmd/index.sqlite, mounted into the container for the ~2 GB model
# cache) is never polluted by test collections/probes. qmd's store.js checks
# INDEX_PATH first; the model cache still comes from XDG_CACHE_HOME (shared).
# This also lets the host and container use qmd concurrently without lock
# contention on the same index.
export INDEX_PATH="/tmp/qmd-test/index.sqlite"
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

# claude
devbot -p "/devbot:audit" || echo "WARN: devbot run failed (exit $?)"
_phase "agent audit"

# Remove the test git repo when the container exits so the host mount
# (/app = tests/test-project) stays a plain directory inside the dev-bot repo.
# NOTE: not `exec` — the EXIT trap must fire after the interactive shell ends.
cleanup_test_repo() {
  if [ -e /app/.git ]; then
    rm -rf /app/.git
    echo "(removed test git repo from /app)"
  fi
}
trap cleanup_test_repo EXIT

_show_durations

echo
echo "=== Test done — you are inside the container (uid $(id -u)). Run 'exit' to leave. ==="
bash -i
