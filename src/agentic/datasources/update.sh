#!/usr/bin/env bash
# src/agentic/datasources/update.sh
# Re-ensures the pinned image and re-renders the gateway artifacts.
#
# Deliberately does NOT bump the pin to the latest release: the generated
# tools.yaml is read by exactly the pinned version, and toolbox's source/tool
# schema is versioned with the binary. Upgrading is an explicit act — edit
# versions.env, then run `devbot update`.
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec bash "${MODULE_DIR}/install.sh" "$@"
