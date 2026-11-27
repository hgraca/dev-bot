#!/usr/bin/env bash
# Install herdr and wire its devbot-managed shell wrapper.
#
# Idempotent: an installed herdr is left alone, an unchanged wrapper block is not
# rewritten, and both shell rcs are converged whatever their previous state.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

_herdr_main install
