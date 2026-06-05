#!/usr/bin/env bash
# src/agentic/modules/qmd/functions.sh
# Shared helpers — delegates to src/functions.sh for boilerplate.

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../functions.sh
source "${MODULE_DIR}/../../../functions.sh"
