#!/usr/bin/env bash
# Test fixture: a minimal forensics source adapter used by sources_tests.bats.
set -euo pipefail

case "${1:-}" in
  meta) printf '{"source":"fixture","capabilities":[]}\n' ;;
  doctor) printf '{"ok":true,"source":"fixture"}\n' ;;
  fetch) printf '{"ok":true,"pull_requests":[],"errors":[]}\n' ;;
  *)
    echo "ERROR: unknown verb '${1:-}'" >&2
    exit 2
    ;;
esac
