#!/usr/bin/env bash
# Shared helpers — delegates to src/_shared/functions.sh for boilerplate.

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

# ie: LOCAL_MODELS=(qwen2.5-coder:7b)
LOCAL_MODELS=()
