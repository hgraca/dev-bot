#!/usr/bin/env bash
# src/agentic/repomix/functions.sh
# Shared helpers for repomix module scripts.

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"
