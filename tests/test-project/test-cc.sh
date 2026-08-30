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

# Optional branch to install (default: main), forwarded to the inner script
# and used by the devbot install line in test-reinit.sh.
BRANCH="${1:-main}"

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
# qmd llama models (qmd pull is a no-op once cached). The test's qmd SQLite
# INDEX is isolated via INDEX_PATH (set in test-cc-inner.sh), so the shared
# mount only carries models — the host index is never written by the test.
# Share the host caches so container runs never re-pay cold-start costs:
# - ~/.cache/qmd: the ~2 GB qmd llama models (qmd pull is a no-op once cached)
# - ~/.cache/opencode: opencode models.json + plugin packages (~385 MB)
# - ~/.cache/bun: Bun's TS-compile cache (plugin loading)
# - ~/.npm: the npx cache (MCP server packages)
# Pre-create the dirs so docker does not mount root-owned ones.
mkdir -p "${HOME}/.cache/qmd" "${HOME}/.cache/opencode" "${HOME}/.cache/bun" "${HOME}/.npm"

echo "Starting container as uid $(id -u):$(id -g) — running the Claude Code test, then dropping you into a shell..."

# Pass the host GPU through if present (NVIDIA --gpus all, else the /dev/dri
# render nodes) so qmd embeddings / ollama run with acceleration.
GPU_ARGS=()
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
  GPU_ARGS=(--gpus all)
elif ls /dev/dri/renderD* >/dev/null 2>&1; then
  GPU_ARGS=(--device /dev/dri)
fi

# Fixed container name so an interrupted/detached run can always be found and
# killed (--rm alone only fires when the container exits cleanly — Ctrl+C or a
# dropped terminal leaves it running). The trap force-removes it whenever this
# script exits, and any stale container from an aborted run is dropped first.
CONTAINER_NAME="devbot-test-cc"
cleanup_container() {
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
}
trap cleanup_container EXIT INT TERM
cleanup_container

docker run -it --rm --name "${CONTAINER_NAME}" \
  --network host \
  "${GPU_ARGS[@]}" \
  -v "${SCRIPT_DIR}:/app" \
  -v "${HOME}/.ssh:/tmp/ssh:ro" \
  -v "${HOME}/.local/share/opencode:/home/ubuntu/.local/share/opencode" \
  -v "${HOME}/.cache/qmd:/home/ubuntu/.cache/qmd" \
  -v "${HOME}/.cache/opencode:/home/ubuntu/.cache/opencode" \
  -v "${HOME}/.cache/bun:/home/ubuntu/.cache/bun" \
  -v "${HOME}/.npm:/home/ubuntu/.npm" \
  -e "JETBRAINS_PROJECT_PATH=${SCRIPT_DIR}" \
  -e "DEV_BOT_TEST_BRANCH=${BRANCH}" \
  -w /app \
  --user "$(id -u):$(id -g)" \
  devbot-test bash /app/test-cc-inner.sh

# Belt-and-braces: after a normal exit the --rm already removed it; this is a
# no-op then, but covers any edge where docker run returned without cleanup.
cleanup_container
