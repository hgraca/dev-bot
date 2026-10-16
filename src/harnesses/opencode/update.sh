#!/usr/bin/env bash
# =============================================================================
# src/harnesses/opencode/update.sh
# Provision the pinned Intelephense when devbot updates, so a machine picks up a
# bumped pin on `devbot update` and not only `devbot install`.
#
# The pin is bumped by a deliberate repo commit — never by a script. Rewriting
# the tracked pin here would leave the release checkout dirty and risk the
# update auto-stash, and would not distribute the bump to consumers anyway.
#
# GATE: Must work on Ubuntu, Fedora, and macOS.
# =============================================================================

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# install.sh is idempotent: it provisions the pinned version if absent.
"${MODULE_DIR}/install.sh"
