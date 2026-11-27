#!/usr/bin/env bash
# Move herdr to the latest release and re-render its shell wrapper.
#
# The wrapper is what `devbot update` refreshes: a herdr function changed in
# this repo reaches the machine here, without a manual edit of ~/.bashrc.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

_herdr_main update
