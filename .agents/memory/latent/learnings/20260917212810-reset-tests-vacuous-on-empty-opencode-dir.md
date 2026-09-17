---
date: 2026-09-17
keywords: ["bats", "reset", "idempotent", "reinit"]
---

# Second-reset assertions go vacuous when the fixture's .opencode/ is empty

reset.sh ends its symlink cleanup with `find "${dir}" -type d -empty -delete` and exits early at `[[ ! -d "${OPENCODE_DIR}" ]]`. A reset test whose fixture creates a bare, empty `.opencode/` therefore loses the directory on the first run, and the second run never reaches the refresh loop — leaving a before/after byte-idempotency comparison silently comparing a file the second reset never touched. Both `reset_tests.bats` idempotency tests had this shape: the playwright one introduced in `8cf7b905` and the older D7 one predating it. Both passed while proving nothing.

Fix: keep a user file (e.g. `.opencode/agents/user-agent.md`) in the fixture so the directory survives the cleanup, and `refute_output --partial "nothing to reset"` before the comparison so a fixture that loses the directory fails loudly. Verified red by restoring the empty `.opencode/`: each test then fails on `No .opencode/ directory — nothing to reset`.

Generalisation: a reset or idempotency test needs a fixture that survives the operation under test, plus an explicit assertion that the second run did work. A green before/after comparison on its own proves nothing — it is satisfied equally by "no change" and by "the run did nothing at all".
