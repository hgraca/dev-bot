#!/usr/bin/env bash
# Upgrade ghostty and repeat the default-terminal hint.
#
# Unattended-safe: `devbot update --auto` may run this at session start, so every
# privileged step uses `sudo -n` and skips with a warning rather than blocking on
# a password prompt.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

_ghostty_main update
