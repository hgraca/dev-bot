#!/usr/bin/env bash
# =============================================================================
# test-oc-inner.sh — runs INSIDE the devbot-test container, invoked by the
# test-oc.sh launcher. Provisions prereqs, installs opencode if missing,
# re-inits devbot, runs the devbot-audit command through opencode, then drops
# to an interactive shell so you can keep working in the same container.
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
  # harness session runs (oc disables the audit) — ensure it exists first.
  mkdir -p /app/.agents/logs 2>/dev/null || true
  {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] test phase durations:"
    for entry in "${PHASES[@]}"; do
      printf '  %-24s %4ds\n' "${entry%%:*}" "${entry##*:}"
    done
    printf '  %-24s %4ds\n' "TOTAL" "${total}"
  } >> /app/.agents/logs/test-durations.log 2>/dev/null || true
}

# Ensure the project config targets the opencode harness only.
set_harness() {
  python3 - <<'PY'
import json, sys
path = "/app/.devbot.project.jsonc"
try:
    with open(path) as f:
        d = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    d = {}
d["harness"] = "opencode"
d.setdefault("modules", {})["opencode"] = True
d.setdefault("modules", {})["claudecode"] = False
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

# opencode is baked into the image at ~/.opencode/bin — make it available in
# this shell (the installer only appends it to .bashrc).
export PATH="$HOME/.opencode/bin:$PATH"

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

# Grant the opencode install dir through opencode's external_directory
# permission (the agent audits the harness itself). Merges; no-op if absent.
python3 "${HOME}/.local/share/dev-bot/src/_shared/upsert_opencode_permission.py" \
  "${PWD}/opencode.jsonc" "${HOME}/.opencode/**" 2>/dev/null || true
_phase "opencode grant"

#echo
#echo "doing agent audit..."
#echo
## Run the audit command body through opencode.
#CMD_BODY=$(cat .agents/commands/devbot/audit.md | awk 'n < 2 { if (/^---[[:space:]]*$/) n++; next } { print }')
#opencode run "$CMD_BODY" || echo "WARN: opencode run failed (exit $?) — likely missing model credentials"
#_phase "agent audit"

# Remove the test git repo when the container exits so the host mount
# (/app = this run's isolated copy) stays a plain directory. NOTE: not `exec` —
# the EXIT trap must fire after the interactive shell ends.
cleanup_test_repo() {
  if [ -e /app/.git ]; then
    rm -rf /app/.git
    echo "(removed test git repo from /app)"
  fi

  # Stage the opencode harness logs into /app so the host launcher can sync
  # them back after the container is removed. ~/.local/share/opencode is a
  # host mount, but staging a per-run copy keeps the sync uniform and avoids
  # picking up logs from OTHER opencode sessions sharing that mount.
  local oc_log_dir="$HOME/.local/share/opencode/log"
  if [ -d "${oc_log_dir}" ]; then
    mkdir -p /app/.agents/logs/harness
    cp -R "${oc_log_dir}/." /app/.agents/logs/harness/ 2>/dev/null || true
    echo "(staged opencode harness logs to /app/.agents/logs/harness)"
  fi
}
trap cleanup_test_repo EXIT

_show_durations

# Non-interactive mode (DEVBOT_TEST_NONINTERACTIVE=1, forwarded by the
# launcher): finish the test and exit cleanly instead of parking at bash -i —
# the EXIT trap stages the harness logs and the host launcher syncs outputs
# back to the fixture. For automation/CI.
if [[ "${DEVBOT_TEST_NONINTERACTIVE:-0}" == "1" ]]; then
  echo "=== Test complete (non-interactive) — exiting ==="
  exit 0
fi

echo
echo "=== Test done — you are inside the container (uid $(id -u)). Run 'exit' to leave. ==="
bash -i
