---
date: 2026-09-15
keywords: ["shell", "bats", "testing", "lifecycle", "verification"]
trigger-on: ["shell-script-testing", "bats-file-shape-assertions"]
---

## A shell script needs a test that executes it — file-shape assertions pass while it exits 127

Assertions such as "the script exists", "it is executable", and "it contains X" cannot fail when the script is broken. A lifecycle script that had lost the helper it called (`command not found`, exit 127) sat behind a green suite because every test only inspected the file: `[ -f update.sh ]`, `grep -q ...`. The suite green-lit a script no one had run.

For anything with behaviour, add at least one test that **executes** it:

```bash
@test "update.sh runs cleanly" {
  sandbox="$(mktemp -d)"
  mkdir -p "${sandbox}/storage/x"          # a sandboxed root the script writes to
  # stub every external tool so the test never touches the network
  printf '#!/usr/bin/env bash\nexit 0\n' > "${sandbox}/mockbin/npx"
  chmod +x "${sandbox}/mockbin/npx"

  run env ROOT="${sandbox}" PATH="${sandbox}/mockbin:${PATH}" bash "${MODULE_DIR}/update.sh"

  assert_success                                  # catches exit 127 and friends
  refute_output --partial "command not found"
  refute_output --partial "UNEXPECTED"            # a stub that should never fire
  rm -rf "${sandbox}"
}
```

Practical notes: make the script's root overridable by an env var so it can be sandboxed; stub each external tool and have the stubs fail loudly if an unexpected one runs; and assert on the side effect (`[ -f ... ]` on the file that should have been produced), not just on the exit code. Where behaviour genuinely cannot be executed in a test, still assert the absence of the specific broken construct — but prefer executing.
