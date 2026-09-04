#!/usr/bin/env bash
# =============================================================================
# test-oc.sh — HOST launcher. Builds the devbot-test image (if needed), starts
# a container as your host uid with the project mounted at /app, runs the
# opencode test inside it (test-oc-inner.sh), then leaves you in an interactive
# shell in the same container so you can keep working after the test.
#
# Usage:
#   ./test-oc.sh [<branch>]
#
# <branch> is the dev-bot branch to install for the test (default: main).
#   e.g. ./test-oc.sh my-feature-branch
#
# Inside the container afterwards: 'exit' leaves (container is removed with
# --rm).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Optional branch to install (default: main) and --headless flag (run the
# audit headlessly instead of dropping to a shell to run it manually).
# Usage: ./test-oc.sh [<branch>] [--headless]  (flags may appear anywhere)
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

# The container routes to the host ollama via --network host: localhost:18434
# inside the container is the host's dev-bot-ollama. Require it to be up
# before starting the test.
if ! curl -s --max-time 5 http://localhost:18434/api/tags >/dev/null 2>&1; then
  echo "ERROR: ollama is not reachable on the host at http://localhost:18434." >&2
  echo "       Start devbot on the host first (devbot up) so the ollama API comes online." >&2
  exit 1
fi

# Share the host qmd model cache so container runs never re-download the ~2 GB
# qmd llama models (qmd pull is a no-op once cached). Pre-create the
# dir so docker does not mount a root-owned one. The test's qmd SQLite INDEX
# is a DEDICATED devbot-test db under this same mount (~/.cache/qmd/devbot-test,
# set via INDEX_PATH in test-oc-inner.sh) — shared by parallel cc + oc runs so
# the global store embeds once, serialized by qmd/init.sh's .llama.lock; the
# host's real index is never written by the test.
# Share the host caches so container runs never re-pay cold-start costs:
# - ~/.cache/qmd: the ~2 GB qmd llama models (qmd pull is a no-op once cached)
# - ~/.cache/opencode: opencode models.json + plugin packages (~385 MB)
# - ~/.cache/bun: Bun's TS-compile cache (plugin loading)
# - ~/.npm: the npx cache (MCP server packages)
# Pre-create the dirs so docker does not mount root-owned ones.
mkdir -p "${HOME}/.cache/qmd" "${HOME}/.cache/opencode" "${HOME}/.cache/bun" "${HOME}/.npm"

echo "Starting container as uid $(id -u):$(id -g) — running the opencode test, then dropping you into a shell..."

# Pass the host GPU through if present (NVIDIA --gpus all, else the /dev/dri
# render nodes) so qmd embeddings / ollama run with acceleration.
GPU_ARGS=()
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
  GPU_ARGS=(--gpus all)
elif ls /dev/dri/renderD* >/dev/null 2>&1; then
  GPU_ARGS=(--device /dev/dri)
fi

# Isolated per-run fixture + parallel-safe container management. Each run gets
# its OWN copy of the fixture mounted at /app and its OWN container name (pid-
# suffixed), so cc and oc — or two runs of the same harness — can execute in
# parallel without racing over .devbot.project.jsonc, the harness wiring dirs,
# the nested .git, or the audit-report NN sequence.
# shellcheck source=./test-lib.sh
source "${SCRIPT_DIR}/test-lib.sh"

RUN_DIR="$(run_dir_create "${SCRIPT_DIR}" "oc")"
CONTAINER_NAME="devbot-test-oc-$$"

cleanup() {
  # Idempotent: runs once from the EXIT trap (also fired by INT/TERM). Kill the
  # container FIRST (so on Ctrl+C the sync reads a quiescent /app — on normal
  # exit the container is already gone and this is a no-op), then sync durable
  # outputs (audit report + logs) back to the real fixture and drop the
  # isolated copy. A second call is a safe no-op.
  docker rm -f "${CONTAINER_NAME:-}" >/dev/null 2>&1 || true
  if [[ -d "${RUN_DIR:-}" ]]; then
    sync_run_outputs "${RUN_DIR}" "${SCRIPT_DIR}" "oc"
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

docker run -it --rm --name "${CONTAINER_NAME}" \
  --network host \
  "${GPU_ARGS[@]}" \
  "${COMPOSER_ARGS[@]+"${COMPOSER_ARGS[@]}"}" \
  -v "${RUN_DIR}:/app" \
  -v "${HOME}/.ssh:/tmp/ssh:ro" \
  -v "${HOME}/.local/share/opencode:/home/ubuntu/.local/share/opencode" \
  -v "${HOME}/.cache/qmd:/home/ubuntu/.cache/qmd" \
  -v "${HOME}/.cache/opencode:/home/ubuntu/.cache/opencode" \
  -v "${HOME}/.cache/bun:/home/ubuntu/.cache/bun" \
  -v "${HOME}/.npm:/home/ubuntu/.npm" \
  -e "JETBRAINS_PROJECT_PATH=${SCRIPT_DIR}" \
  -e "DEV_BOT_TEST_BRANCH=${BRANCH}" \
  -e "DEVBOT_TEST_NONINTERACTIVE=${DEVBOT_TEST_NONINTERACTIVE:-0}" \
  -e "DEVBOT_TEST_HEADLESS=${HEADLESS}" \
  -e "DEVBOT_TEST_CONTAINER_NAME=${CONTAINER_NAME}" \
  -e "DEVBOT_TEST_CLAUDE_MODEL=${DEVBOT_TEST_CLAUDE_MODEL:-}" \
  -w /app \
  --user "$(id -u):$(id -g)" \
  devbot-test bash /app/test-oc-inner.sh

# Belt-and-braces: after a normal exit the --rm already removed it; this is a
# no-op then (RUN_DIR already gone), but covers any edge where docker run
# returned without the trap firing.
cleanup
