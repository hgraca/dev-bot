#!/usr/bin/env bash
# Test fixture: a plugin whose `meta` output is not JSON.
set -euo pipefail

case "${1:-}" in
  meta) echo 'this is not json' ;;
  *) exit 1 ;;
esac
