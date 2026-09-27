#!/usr/bin/env bash
# Test fixture: a plugin whose `meta` JSON is missing the required `lang` key.
set -euo pipefail

case "${1:-}" in
  meta) echo '{"extensions":[".zz"]}' ;;
  *) exit 1 ;;
esac
