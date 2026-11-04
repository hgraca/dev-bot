#!/usr/bin/env bash
# =============================================================================
# bin/reinit.sh
# Deprecated alias for `bin/init.sh`.
#
# `devbot init` already resets an initialised project before wiring it, so this
# command is a pure alias: same arguments, same detection, same behaviour. The
# file is kept because the bare-start auto-reinit, the e2e fixtures and the
# documentation still reference `devbot reinit`.
# =============================================================================

set -euo pipefail

DEV_BOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEV_BOT_ROOT

exec bash "${DEV_BOT_ROOT}/bin/init.sh" "$@"
