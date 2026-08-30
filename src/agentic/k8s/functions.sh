#!/usr/bin/env bash
# src/agentic/k8s/functions.sh
# Thin wrapper: sources the root shared library.
set -euo pipefail
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export MODULE_DIR
source "$MODULE_DIR/../../_shared/functions.sh"
