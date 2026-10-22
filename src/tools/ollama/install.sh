#!/usr/bin/env bash
# Install ollama — nothing to install on the host: the service runs in Docker.
#
# No image is pulled here. `bin/install.sh` runs install scripts with `--all`,
# so this one runs even when the ollama module is disabled (it is off by
# default) — and the image is 4.8 GB. `docker compose up` pulls it on the first
# `up` that actually needs it, and `bin/up.sh` announces the download first.
#
# GPU detection no longer lives here either: _devbot_detect_gpu (src/_shared/
# functions.sh) records gpu_enabled from bin/install.sh / bin/update.sh, so the
# result survives the module being disabled in the `modules` map.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  _info "ollama"
  _skip "ollama/ollama:latest is pulled by docker compose on first use — nothing downloaded now"
  _ok "ollama ready"
}

main
