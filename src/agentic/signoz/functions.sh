#!/usr/bin/env bash
# src/agentic/signoz/functions.sh
# Shared helpers for SigNoz module scripts (install.sh, update.sh, init.sh).

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../_shared/functions.sh
source "${MODULE_DIR}/../../_shared/functions.sh"

# Resolve the storage directory for SigNoz assets (skills, README).
_signoz_storage_dir() {
  echo "${DEV_BOT_ROOT}/storage/signoz"
}
