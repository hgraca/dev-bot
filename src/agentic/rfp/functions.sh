#!/usr/bin/env bash
# src/agentic/rfp/functions.sh
# Shared helpers — delegates to src/_shared/functions.sh for boilerplate.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export MODULE_DIR

# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"
