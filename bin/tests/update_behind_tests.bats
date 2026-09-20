#!/usr/bin/env bats
# =============================================================================
# bin/tests/update_behind_tests.bats
# bin/update.sh — Path A: strictly behind the newest release.
# Covers the detach-jump, the dirty-tree stash/pop round trip, the release
# recording + global-config reconciliation that follows a jump, the --auto
# variant, and shallow (--depth 1) installs that are behind.
#
# Fixtures live in update_helpers.bash.
# =============================================================================

load update_helpers

setup() { _update_setup; }
teardown() { _update_teardown; }

# ── Path A: strictly behind -> detach-jump ───────────────────────────────────

@test "behind: detaches onto the newest tag and runs the refresh block" {
  _new_sandbox "1.0.0:1.1.0"
  _publish_release "g.txt" "release 1.2.0" "1.2.0"
  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  _assert_detached_at_newest_tag
  _refresh_ran
  [[ "$UPDATE_OUTPUT" == *"1.2.0"* ]]
  # The post-jump refresh runs _devbot_detect_gpu (bin/update.sh). The sandbox
  # install has no .devbot.global.jsonc, so the helper hits its first guard —
  # asserting that message proves the GPU-detection call site is reached
  # (without depending on the host's GPU state).
  [[ "$UPDATE_OUTPUT" == *"gpu detection skipped"* ]]
}

@test "behind with dirty tree: stashes, jumps, reapplies cleanly" {
  _new_sandbox "1.0.0:1.1.0"
  _publish_release "g.txt" "release 1.2.0" "1.2.0"
  # Local unstaged edit to a file untouched by the new release.
  printf 'local tweak\n' >> "${INSTALL}/f.txt"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  _assert_detached_at_newest_tag
  _refresh_ran
  # Stash popped cleanly: edit restored, no stash left behind.
  grep -q 'local tweak' "${INSTALL}/f.txt"
  run git -C "${INSTALL}" stash list
  [ "$status" -eq 0 ]
  [[ -z "$output" ]]
}

@test "behind with conflicting stash pop: warns and continues past it" {
  _new_sandbox "1.0.0:1.1.0"
  # New release touches f.txt (the same file the local edit touches) -> pop
  # will conflict. Feed a keypress on stdin for the ack.
  _publish_release "f.txt" "release 1.2.0" "1.2.0"
  printf 'local tweak\n' >> "${INSTALL}/f.txt"

  run bash -c "printf 'x\n' | bash '${INSTALL}/bin/update.sh'"
  UPDATE_STATUS="$status"
  UPDATE_OUTPUT="$output"

  [ "$UPDATE_STATUS" -eq 0 ]
  _refresh_ran
  # The conflict warning is shown (the ack wait itself is not observable on a
  # non-tty stdin, but the warn-and-continue contract is).
  [[ "$UPDATE_OUTPUT" == *"conflict"* ]]
  # Conflict left in the working tree for the user to fix later.
  run git -C "${INSTALL}" status --porcelain --untracked-files=no
  [[ "$output" == *"UU f.txt"* || "$output" == *"AA f.txt"* || "$output" == *"U"* ]]
}

# ── Version recording (the per-project reinit trigger) ───────────────────────

@test "behind: records the release tag in the global config version" {
  _new_sandbox "1.0.0:1.1.0"
  printf '{\n  "gpu_enabled": false,\n  "version": ""\n}\n' > "${INSTALL}/.devbot.global.jsonc"
  _publish_release "g.txt" "release 1.2.0" "1.2.0"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  assert_equal \
    "$(python3 "${INSTALL}/src/_shared/read_jsonc.py" "${INSTALL}/.devbot.global.jsonc" version)" \
    "1.2.0"
}

@test "behind: reconciles the global config against the dist schema" {
  _new_sandbox "1.0.0:1.1.0"
  # Dist schema gained a key and retired another; the runtime config drifts.
  cat > "${INSTALL}/.devbot.global.dist.jsonc" <<'JSONC_EOF'
{
  "version": "",
  "gpu_enabled": false,
  "new_key": "from-dist" // added upstream
}
JSONC_EOF
  cat > "${INSTALL}/.devbot.global.jsonc" <<'JSONC_EOF'
{
  "version": "",
  "gpu_enabled": true,
  "retired_key": true
}
JSONC_EOF
  _publish_release "g.txt" "release 1.2.0" "1.2.0"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  # The added key lands with its dist value; the retired key is gone; the
  # runtime value of a shared key is preserved (gpu_enabled stays true).
  assert_equal \
    "$(python3 "${INSTALL}/src/_shared/read_jsonc.py" "${INSTALL}/.devbot.global.jsonc" new_key)" \
    "from-dist"
  run python3 -c "
import sys
sys.path.insert(0, '${INSTALL}/src/_shared')
from read_jsonc import load_jsonc
d = load_jsonc('${INSTALL}/.devbot.global.jsonc')
assert 'retired_key' not in d, d
assert d['gpu_enabled'] is True, d
print('RECONCILED')
"
  assert_success
  assert_output "RECONCILED"
  [[ "$UPDATE_OUTPUT" == *"Global config reconciliation"* ]]
}

@test "behind: a broken dist config does not abort the update" {
  _new_sandbox "1.0.0:1.1.0"
  # Runtime config is valid; the dist template is unparseable, so the
  # reconciler errors. Update must warn and continue (never abort on it).
  printf '{\n  "version": \n' > "${INSTALL}/.devbot.global.dist.jsonc"
  printf '{\n  "gpu_enabled": false,\n  "version": ""\n}\n' > "${INSTALL}/.devbot.global.jsonc"
  _publish_release "g.txt" "release 1.2.0" "1.2.0"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  [[ "$UPDATE_OUTPUT" == *"Global config reconciliation"* ]]
  [[ "$UPDATE_OUTPUT" == *"left as-is"* ]]
  # The release is still recorded — the reconcile failure did not abort it.
  assert_equal \
    "$(python3 "${INSTALL}/src/_shared/read_jsonc.py" "${INSTALL}/.devbot.global.jsonc" version)" \
    "1.2.0"
}

@test "a real update does not run reinit (the version bump drives it lazily)" {
  _new_sandbox "1.0.0:1.1.0"
  printf '{\n  "gpu_enabled": false,\n  "version": ""\n}\n' > "${INSTALL}/.devbot.global.jsonc"
  # A reinit stub that would leave a marker if update invoked it.
  cat > "${INSTALL}/bin/reinit.sh" <<EOF
#!/usr/bin/env bash
touch "${SANDBOX}/reinit-ran"
EOF
  chmod +x "${INSTALL}/bin/reinit.sh"
  _publish_release "g.txt" "release 1.2.0" "1.2.0"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  [ ! -e "${SANDBOX}/reinit-ran" ]
}

# ── Auto mode, behind ────────────────────────────────────────────────────────

@test "--auto behind: updates and records the version" {
  _new_sandbox "1.0.0:1.1.0"
  printf '{\n  "gpu_enabled": false,\n  "version": ""\n}\n' > "${INSTALL}/.devbot.global.jsonc"
  _publish_release "g.txt" "release 1.2.0" "1.2.0"

  _run_update --auto

  [ "$UPDATE_STATUS" -eq 0 ]
  _assert_detached_at_newest_tag
  assert_equal \
    "$(python3 "${INSTALL}/src/_shared/read_jsonc.py" "${INSTALL}/.devbot.global.jsonc" version)" \
    "1.2.0"
}

# ── Shallow installs (install.sh clones with --depth 1) ──────────────────────

@test "shallow install: a behind branch still updates" {
  # INSTALL is a depth-1 clone detached at 1.0.0; fetching tags must still
  # connect 1.1.0 to HEAD and classify it behind.
  _new_shallow_sandbox 1.0.0
  _run_update --auto

  [ "$UPDATE_STATUS" -eq 0 ]
  assert_equal "$(git -C "${INSTALL}" rev-parse HEAD)" "$(git -C "${INSTALL}" rev-parse '1.1.0^{commit}')"
  _refresh_ran
}
