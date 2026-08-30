# dev-bot-test container: deps baked in, so the interactive run never needs
# root — you run as your own host uid and every file written into /app is
# yours (no chown cleanup needed).
#
# Build once:
#   docker build -t devbot-test .
#
# Run:
#   docker run -it --rm \
#     -v "$PWD:/app" \
#     -v "$HOME/.ssh:/tmp/ssh:ro" \
#     -w /app \
#     --user "$(id -u):$(id -g)" \
#     devbot-test bash
#
# The base image's default `ubuntu` user is uid 1000 — matching your host uid
# (change it if yours differs). It gets NOPASSWD sudo so the test scripts can
# apt-get without running the container as root.
#
# nodejs/npm from ubuntu (node 22). Node 24 via NodeSource was tried but npm 11
# blocks install scripts by default, which breaks qmd's native deps
# (node-llama-cpp, tree-sitter) — node 22's npm 9 runs them normally. The
# EBADENGINE warning on some deps is cosmetic. build-essential: qmd's
# better-sqlite3 compiles from source via node-gyp.
#
# opencode + claude are baked in so the test doesn't reinstall them per
# container: opencode installs to the ubuntu user's ~/.opencode/bin (run as
# that user so its runtime files are user-owned); the claude CLI is a global
# npm package.
FROM ubuntu

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates git openssh-client python3 sudo nodejs npm docker.io build-essential jq gzip php-cli php-mbstring php-xml \
 && mkdir -p /home/ubuntu/.local/share /home/ubuntu/.local/lib /home/ubuntu/.local/bin \
 && chown -R ubuntu:ubuntu /home/ubuntu/.local \
 && curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb -o /tmp/cuda-keyring.deb \
 && dpkg -i /tmp/cuda-keyring.deb \
 && apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends cuda-cudart-12-6 libcublas-12-6 \
 && rm -f /tmp/cuda-keyring.deb \
 && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/devuser \
 && npm install -g @anthropic-ai/claude-code @playwright/mcp@0.0.79 \
 && npx playwright install-deps chromium \
 && su - ubuntu -c 'npm config set prefix "$HOME/.local" 2>/dev/null && npx -y @playwright/mcp@0.0.79 install-browser chrome-for-testing && npm install -g @tobilu/qmd' \
 && su - ubuntu -c 'npx -y chrome-devtools-mcp@latest --help >/dev/null 2>&1 || true'

# chrome-devtools-mcp bake above: pre-fetches the package into the ubuntu
# user's npx cache (~/.npm/_npx) so the MCP server launch never blocks on a
# first-run `npm exec` fetch (a ~10-20 s part of opencode's cold startup).

# qmd models are NOT baked: the test launchers mount the host qmd cache
# (~/.cache/qmd) into the container, so the ~2 GB llama models (embedding +
# query-expansion 1.7B + Qwen3-Reranker 0.6B) are provided by the mount. The
# test-reinit.sh guard runs `qmd pull` (non-fatal) only when the mounted cache
# is empty — one-time, then persisted on the host.
RUN su - ubuntu -c 'curl -fsSL https://opencode.ai/install | bash' \
 && su - ubuntu -c 'mkdir -p "$HOME/.cache/opencode/packages/opencode-codebase-index@latest" && npm install --no-save --no-audit --no-fund --prefix "$HOME/.cache/opencode/packages/opencode-codebase-index@latest" opencode-codebase-index@0.25.1'

# opencode-codebase-index pre-seed above: opencode's runtime fetch extracts
# the plugin package progressively, and the plugin resolves its native binding
# (native/*.node) once at load — a load mid-extraction silently degrades it to
# the mock binding (no parsing / indexing) for the whole session. Seeding the
# cache to a complete state at build time makes opencode reuse it (verified:
# native modules present, no load error). Keep the pinned version in sync with
# test-reinit.sh.

# CUDA user-space libs (runtime + cuBLAS) so qmd's llama can offload to the GPU
# passed through via --gpus all. The driver lib is mounted by the runtime; the
# user-space libs must live in the image.
ENV LD_LIBRARY_PATH=/usr/local/cuda-12.6/targets/x86_64-linux/lib
