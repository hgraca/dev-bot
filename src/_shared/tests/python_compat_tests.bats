#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/python_compat_tests.bats
# Regression guard for audit-25 F1/F3: dev-bot Python tools crashed on macOS
# stock /usr/bin/python3 (3.9.6) with `TypeError: unsupported operand type(s)
# for |: 'type' and 'NoneType'` because PEP 604 union annotations (str | None)
# are evaluated eagerly at import time and require Python >= 3.10.
#
# The fix is `from __future__ import annotations` as the first import in every
# flagged file — it defers annotation evaluation to strings, restoring
# compatibility back to Python 3.7+. This test asserts the marker is present
# before any function definition in every file that uses PEP 604 unions.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  DEV_BOT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"

  # Every Python tool known to use PEP 604 union annotations (str | None,
  # list[str] | None, tuple[str | None, ...]) WITHOUT a __future__ import —
  # the blast radius confirmed by grep in audit-25.
  FLAGGED_FILES=(
    "${DEV_BOT_ROOT}/src/_shared/editorconfig.py"
    "${DEV_BOT_ROOT}/src/agentic/format-md/tools/format-md.py"
    "${DEV_BOT_ROOT}/src/agentic/format-json/tools/format-json.py"
    "${DEV_BOT_ROOT}/src/agentic/format-yml/tools/format-yml.py"
    "${DEV_BOT_ROOT}/src/agentic/git/tools/git-report.py"
    "${DEV_BOT_ROOT}/src/agentic/memory/tools/search-memories/search-memories.py"
  )
}

@test "audit-25: every PEP 604-annotated tool carries 'from __future__ import annotations'" {
  command -v python3 &>/dev/null || skip "python3 not installed"

  local failed=""
  local f
  for f in "${FLAGGED_FILES[@]}"; do
    [[ -f "$f" ]] || { failed="${failed}\n  MISSING FILE: $f"; continue; }
    if ! python3 - "$f" <<'PYEOF'
import ast
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    tree = ast.parse(fh.read())

has_future = any(
    isinstance(node, ast.ImportFrom)
    and node.module == "__future__"
    and any(alias.name == "annotations" for alias in node.names)
    for node in tree.body
)
sys.exit(0 if has_future else 1)
PYEOF
    then
      failed="${failed}\n  $f"
    fi
  done

  if [[ -n "$failed" ]]; then
    fail "files missing 'from __future__ import annotations' (breaks on Python < 3.10):${failed}"
  fi
}

@test "audit-25: future import precedes any function/class definition" {
  local f
  for f in "${FLAGGED_FILES[@]}"; do
    [[ -f "$f" ]] || continue
    # The future import must appear before the first top-level def/class so
    # annotations in the earliest functions are deferred too.
    run python3 - "$f" <<'PYEOF'
import ast
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    tree = ast.parse(fh.read())

future_index = None
first_def_index = None
for i, node in enumerate(tree.body):
    if (
        isinstance(node, ast.ImportFrom)
        and node.module == "__future__"
        and any(alias.name == "annotations" for alias in node.names)
    ):
        future_index = i
    elif isinstance(node, (ast.FunctionDef, ast.ClassDef, ast.AsyncFunctionDef)):
        if first_def_index is None:
            first_def_index = i

# A future import is only effective for statements that follow it.
if future_index is None:
    sys.exit(1)
if first_def_index is not None and future_index > first_def_index:
    sys.exit(1)
sys.exit(0)
PYEOF
    assert_success "future import ordering broken in $f"
  done
}
