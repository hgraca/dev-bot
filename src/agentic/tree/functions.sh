#!/usr/bin/env bash
# src/agentic/tree/functions.sh
# Shared helpers — delegates to src/_shared/functions.sh for boilerplate.

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"
