#!/usr/bin/env bash
# =============================================================================
# test-cc.sh — HOST launcher. Builds the devbot-test image (if needed), starts
# a container as your host uid with the project mounted at /app, runs the
# Claude Code test inside it (test-cc-inner.sh), then leaves you in an
# interactive shell in the same container so you can keep working after the
# test.
#
# Usage:
#   ./test-cc.sh [<branch>]
#
# <branch> is the dev-bot branch to install for the test (default: main).
#   e.g. ./test-cc.sh my-feature-branch
#
# Inside the container afterwards: 'exit' leaves (container is removed with
# --rm).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Optional branch to install (default: main) and --headless flag (run the
# audit headlessly instead of dropping to a shell to run it manually).
# Usage: ./test-cc.sh [<branch>] [--headless]  (flags may appear anywhere)
BRANCH="main"
HEADLESS=0
for _arg in "$@"; do
  case "${_arg}" in
    --headless) HEADLESS=1 ;;
    *) BRANCH="${_arg}" ;;
  esac
done

if ! docker image inspect devbot-test >/dev/null 2>&1; then
  echo "Building devbot-test image..."
  docker build -t devbot-test .
fi

# Self-contained: the container runs its OWN docker daemon (the inner script
# starts dockerd; --privileged, no --network host) and dev-bot's shared MCP
# gateways run against it, so nothing depends on the host daemon or host ollama.
# The anonymous /var/lib/docker volume moves the inner data-root off the image's
# overlayfs — nested overlay2 cannot create containers on an overlay backing.
# The codebase-index engine is not exercised (no host network); the shipped
# default is codebase-memory + mdctx.
#
# --privileged and the in-container daemon are a deliberate exception to the
# `devbot:architecture-rules` no-privileged / no-host-networking rules: this is
# a local, disposable test fixture, not a deployed workload.

# Share the host qmd index cache so parallel cc + oc container runs index the
# global store once. qmd is BM25-only — no model download, no embeddings (ADR
# 20260913072905-qmd-bm25-only-no-model-downloads). The test's qmd SQLite INDEX
# is a DEDICATED devbot-test db under this same mount
# (~/.cache/qmd/devbot-test, set via INDEX_PATH in test-cc-inner.sh); the host's
# real index is never written by the test.
# Share the host caches so container runs never re-pay cold-start costs:
# - ~/.cache/qmd: the shared qmd index db (no models — BM25-only)
# - ~/.cache/opencode: opencode models.json + plugin packages (~385 MB)
# - ~/.cache/bun: Bun's TS-compile cache (plugin loading)
# - ~/.npm: the npx cache (MCP server packages)
# Pre-create the dirs so docker does not mount root-owned ones.
mkdir -p "${HOME}/.cache/qmd" "${HOME}/.cache/opencode" "${HOME}/.cache/bun" "${HOME}/.npm"

echo "Starting container as uid $(id -u):$(id -g) — running the Claude Code test, then dropping you into a shell..."

# No GPU passthrough: the test runs no ollama and needs no acceleration.

# Share the host's Claude Code state so the container skips the trust + onboarding
# dialogs. Trust lives in ~/.claude.json — a sibling of the mounted ~/.claude/
# dir, keyed by absolute project path — and the container's project is /app, not
# the host path. Mount the host file READ-ONLY; test-cc-inner.sh seeds a
# container-local copy with /app trusted and never writes the host file. Skipped
# when the host has none, so docker does not create a stray root-owned dir.
CLAUDE_CONFIG_ARGS=()
[[ -f "${HOME}/.claude.json" ]] \
  && CLAUDE_CONFIG_ARGS=(-v "${HOME}/.claude.json:/tmp/host-claude.json:ro")

# Isolated per-run fixture + parallel-safe container management. Each run gets
# its OWN copy of the fixture mounted at /app and its OWN container name (pid-
# suffixed), so cc and oc — or two runs of the same harness — can execute in
# parallel without racing over .devbot.project.jsonc, the harness wiring dirs,
# the nested .git, or the audit-report NN sequence.
# shellcheck source=./test-lib.sh
source "${SCRIPT_DIR}/test-lib.sh"

RUN_DIR="$(run_dir_create "${SCRIPT_DIR}" "cc")"
CONTAINER_NAME="devbot-test-cc-$$"

# The audit report must reach the REAL fixture while the container is still up:
# the interactive shell keeps this launcher alive, so the exit-time sync is too
# late. Bind-mount the fixture's thinking/ dir into the container (below) so the
# audit writes devbot-audit-<NN>.md straight onto the fixture — and reserve that
# id atomically, since a parallel run shares the same dir.
THINKING_DIR="${SCRIPT_DIR}/.agents/memory/thinking"
mkdir -p "${THINKING_DIR}" "${RUN_DIR}/.agents"
AUDIT_NN="$(reserve_audit_nn "${THINKING_DIR}")"
AUDIT_REPORT_NAME="devbot-audit-${AUDIT_NN}.md"

cleanup() {
  # Idempotent: runs once from the EXIT trap (also fired by INT/TERM). Kill the
  # container FIRST (so on Ctrl+C the sync reads a quiescent /app — on normal
  # exit the container is already gone and this is a no-op), then file durable
  # outputs (logs; the report already landed via the mount) back to the real
  # fixture and drop the isolated copy. A second call is a safe no-op.
  # -v: the container's anonymous /var/lib/docker volume is not removed by a
  # force kill, and leaks the inner daemon's images/containers without it.
  docker rm -f -v "${CONTAINER_NAME:-}" >/dev/null 2>&1 || true
  if [[ -d "${RUN_DIR:-}" ]]; then
    sync_run_outputs "${RUN_DIR}" "${SCRIPT_DIR}" "cc" "${AUDIT_REPORT_NAME:-}"
    # Drop this run's reserved slot if the audit never filled it.
    if [[ -n "${AUDIT_REPORT_NAME:-}" && -f "${THINKING_DIR}/${AUDIT_REPORT_NAME}" \
      && ! -s "${THINKING_DIR}/${AUDIT_REPORT_NAME}" ]]; then
      rm -f "${THINKING_DIR}/${AUDIT_REPORT_NAME}" 2>/dev/null || true
    fi
    # Release this run's shared-gateway index entry before dropping the copy it
    # was derived from (best-effort; see codebase_memory_prune_run).
    codebase_memory_prune_run "${RUN_DIR}"
    run_dir_destroy "${RUN_DIR}"
  fi
}
trap cleanup EXIT INT TERM

# Share the host composer cache so `composer install` in the container never
# re-downloads packages. Cross-platform: composer's own cache-dir wins, else
# Linux ~/.cache/composer / macOS ~/Library/Caches/composer. When no host
# cache exists, COMPOSER_ARGS stays empty and the env var is NOT set (composer
# would otherwise silently use an empty container-local dir).
read -r -a COMPOSER_ARGS <<< "$(composer_cache_args)"

# ~/.claude is mounted so the container's claude CLI inherits the HOST claude
# login (~/.claude/.credentials.json) — without it the automated
# `devbot -p "/devbot:audit"` fails with "Not logged in · Please run /login"
# (the opencode harness auths via the separately-mounted ~/.local/share/opencode).
# Runs as the host uid, so file ownership matches and claude can read/write its
# own state (settings, backups) as usual.

# ── Run the container DETACHED; attach interactivity via `docker exec` ───────
# `docker run -it`'s stdin attach has proven unreliable in several terminals
# (typed input reaches neither echo nor the shell, while `docker exec -it`
# works) — so run detached and, once the inner script signals it has finished
# its phases (writes .agents/.test-ready into the host-mounted /app), attach a
# real pty with `docker exec -it`. Phase output streams live via `docker logs`.
echo "Starting ${CONTAINER_NAME} (detached — phases run inside; log follows)..."
docker run -d --rm --name "${CONTAINER_NAME}" \
  --privileged \
  --mount type=volume,dst=/var/lib/docker \
  "${COMPOSER_ARGS[@]+"${COMPOSER_ARGS[@]}"}" \
  "${CLAUDE_CONFIG_ARGS[@]+"${CLAUDE_CONFIG_ARGS[@]}"}" \
  -v "${RUN_DIR}:/app" \
  -v "${SCRIPT_DIR}/.agents/memory/thinking:/app/.agents/memory/thinking" \
  -v "${HOME}/.ssh:/tmp/ssh:ro" \
  -v "${HOME}/.claude:/home/ubuntu/.claude" \
  -v "${HOME}/.local/share/opencode:/home/ubuntu/.local/share/opencode" \
  -v "${HOME}/.cache/qmd:/home/ubuntu/.cache/qmd" \
  -v "${HOME}/.cache/opencode:/home/ubuntu/.cache/opencode" \
  -v "${HOME}/.cache/bun:/home/ubuntu/.cache/bun" \
  -v "${HOME}/.npm:/home/ubuntu/.npm" \
  -e "JETBRAINS_PROJECT_PATH=${SCRIPT_DIR}" \
  -e "DEV_BOT_TEST_BRANCH=${BRANCH}" \
  -e "DEVBOT_AUDIT_NN=${AUDIT_NN}" \
  -e "DEVBOT_TEST_NONINTERACTIVE=${DEVBOT_TEST_NONINTERACTIVE:-0}" \
  -e "DEVBOT_TEST_HEADLESS=${HEADLESS}" \
  -e "DEVBOT_TEST_CONTAINER_NAME=${CONTAINER_NAME}" \
  -e "DEVBOT_TEST_CLAUDE_MODEL=${DEVBOT_TEST_CLAUDE_MODEL:-}" \
  -w /app \
  --user "$(id -u):$(id -g)" \
  devbot-test bash /app/test-cc-inner.sh

# Stream phase output until the inner script signals readiness (or exits).
docker logs -f "${CONTAINER_NAME}" &
LOGS_FOLLOWER=$!

READY_FILE="${RUN_DIR}/.agents/.test-ready"
READY=0
WAITED=0
while (( WAITED < 1800 )); do
  if [[ -f "${READY_FILE}" ]]; then READY=1; break; fi
  if ! docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null | grep -q true; then
    break
  fi
  sleep 2
  WAITED=$((WAITED + 2))
done
kill "${LOGS_FOLLOWER}" 2>/dev/null || true
wait "${LOGS_FOLLOWER}" 2>/dev/null || true

if [[ "${READY}" == "1" ]] \
  && docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null | grep -q true; then
  if [[ "${DEVBOT_TEST_NONINTERACTIVE:-0}" == "1" ]]; then
    echo "=== non-interactive: waiting for container to exit ==="
    while docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null | grep -q true; do sleep 2; done
  else
    echo "=== Phases complete — attaching interactive shell ==="
    echo "    run /devbot:audit manually; type 'exit' to leave and clean up."
    docker exec -it "${CONTAINER_NAME}" bash || true
  fi
elif [[ "${READY}" != "1" ]]; then
  echo "WARN: container did not signal readiness — see the log above." >&2
else
  echo "=== Test complete (container exited). ==="
fi

# Belt-and-braces: the EXIT trap cleans up; this is a no-op on the normal path.
cleanup
