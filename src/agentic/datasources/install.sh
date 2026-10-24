#!/usr/bin/env bash
# src/agentic/datasources/install.sh
# Renders the gateway's runtime artifacts. The pinned mcp-toolbox image is NOT
# pulled here — the module's own up.sh pulls it on first use, and install runs
# with `--all`, so a gateway that a project never enables would download it for
# nothing. Idempotent — safe to re-run.
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "${MODULE_DIR}/../../.." && pwd)}"
export DEV_BOT_ROOT

# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

main() {
  _info "datasources — install"

  # Docker is not required here any more: nothing is pulled and render.sh only
  # writes the gateway's runtime artifacts.
  _skip "datasources — toolbox image ${TOOLBOX_IMAGE}:${TOOLBOX_VERSION} pulled by the module's up.sh on first use"

  # No canary: it would `docker run` the pinned toolbox (pulling it when
  # missing) — the exact install-time download this module stopped doing.
  DATASOURCES_SKIP_CANARY=1 bash "${MODULE_DIR}/render.sh"
}

main "$@"
