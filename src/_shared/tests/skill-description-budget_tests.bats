#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/skill-description-budget_tests.bats
# T2.2: every first-party SCR skill description fits a 400-byte always-on
# budget. Skill descriptions are injected into every session's context (name +
# location + description); oversized descriptions cost tokens on EVERY
# conversation, not only when the skill fires. The description carries the
# trigger only — an imperative clause (ideally ~72 chars, an ideal rather than
# an enforced limit) plus the literal trigger phrases — so 400 bytes is a
# runaway guard, not a target. Vendor skills stay read-only and are excluded by
# scanning src/agentic only.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  BUDGET_BYTES=400

  command -v python3 &>/dev/null || skip "python3 not installed"
}

# Extract (len_bytes, path) pairs for all first-party SKILL.md descriptions.
_scan() {
  python3 - "${PROJECT_ROOT}" <<'PYEOF'
import glob, os, re, sys
root = sys.argv[1]
for f in sorted(glob.glob(os.path.join(root, "src/agentic/**/skills/**/SKILL.md"), recursive=True)):
    text = open(f, encoding="utf-8", errors="replace").read()
    m = re.match(r"^---\n(.*?)\n---", text, re.S)
    fm = m.group(1) if m else ""
    dm = re.search(r"^description:\s*(.*?)(?=^\w+:|\Z)", fm, re.S | re.M)
    desc = dm.group(1).strip() if dm else ""
    print(f"{len(desc.encode())}\t{f}\t{'yes' if dm else 'no'}")
PYEOF
}

@test "first-party skill descriptions fit the 400-byte always-on budget" {
  local violations=""
  local len file present
  while IFS=$'\t' read -r len file present; do
    if [[ "$len" -gt "$BUDGET_BYTES" ]]; then
      violations+="${file} (${len} > ${BUDGET_BYTES}B)\n"
    fi
  done < <(_scan)
  if [[ -n "${violations}" ]]; then
    printf 'Over-budget skill descriptions:\n%b' "${violations}" >&2
    fail "first-party skill descriptions must be at most ${BUDGET_BYTES} bytes"
  fi
}

@test "every first-party skill declares a frontmatter description" {
  # A missing/empty description silently drops the skill from the agent's
  # palette (opencode skill loader behavior).
  local missing=""
  local len file present
  while IFS=$'\t' read -r len file present; do
    if [[ "${present}" != "yes" ]]; then
      missing+="${file}\n"
    fi
  done < <(_scan)
  if [[ -n "${missing}" ]]; then
    printf 'Skills with no frontmatter description:\n%b' "${missing}" >&2
    fail "every first-party skill must declare a frontmatter description"
  fi
}

@test "scan covers the real first-party skill tree (guards against empty globs)" {
  local count
  count="$(_scan | wc -l)"
  (( count >= 50 )) || fail "expected at least 50 first-party skills, scanned ${count}"
}
