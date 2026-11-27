#!/usr/bin/env bash
# Install ghostty and say how to make it the default terminal.
#
# Idempotent: an installed ghostty is left alone. The default-terminal step is
# never run here — it is printed, because it is the user's choice.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

_ghostty_main install
