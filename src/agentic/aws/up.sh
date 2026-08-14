#!/usr/bin/env bash
# src/agentic/aws/up.sh
# Ensure the user is authenticated to AWS before the harness starts.
#
# Runs on `devbot up` / `devbot` (auto-discovered by bin/up.sh, and skipped
# automatically when this module is disabled for the project).
#
# If already authenticated (aws sts get-caller-identity succeeds), do nothing.
# Otherwise trigger `aws login` (browser auth) when stdin is a TTY. Auth
# failures never block the harness from starting.

set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./functions.sh
source "${MODULE_DIR}/functions.sh"

main() {
  _info "aws — ensuring logged in"

  if ! command -v aws &>/dev/null; then
    _skip "aws CLI not installed — run 'devbot install' first"
    return 0
  fi

  if aws sts get-caller-identity &>/dev/null; then
    _ok "AWS credentials valid"
    return 0
  fi

  if [[ ! -t 0 ]]; then
    _warn "Not authenticated and no interactive terminal — run: aws login"
    return 0
  fi

  _step "Not authenticated — running 'aws login' (a browser window will open)..."
  if aws login; then
    _ok "AWS login complete"
  else
    _warn "aws login did not complete — harness will start without AWS auth"
  fi
}

main "$@"
