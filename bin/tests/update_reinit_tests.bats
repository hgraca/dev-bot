#!/usr/bin/env bats
# =============================================================================
# bin/tests/update_reinit_tests.bats
# devbot update reinits every registered project, in parallel, after a clean
# migrate + reconcile, and reports a failing project without aborting the update.
# =============================================================================

load update_helpers

setup_file() { _update_file_setup; }
setup() { _update_setup; }
teardown() { _update_teardown; }

@test "every registered project is reinited in parallel" {
  _new_sandbox "1.0.0:1.1.0"
  local p1="${SANDBOX}/p1" p2="${SANDBOX}/p2" p3="${SANDBOX}/p3"
  mkdir -p "${p1}" "${p2}" "${p3}"
  cat > "${INSTALL}/.devbot.global.jsonc" <<JSONC_EOF
{
  "gpu_enabled": false,
  "version": "",
  "projects": ["${p1}", "${p2}", "${p3}"]
}
JSONC_EOF

  # Barrier: each stub records its arrival and waits for all three. A
  # sequential reinit would make the first stub time out and exit 1.
  export REINIT_BARRIER="${SANDBOX}/barrier"
  export REINIT_EXPECTED=3
  mkdir -p "${REINIT_BARRIER}"
  cat > "${INSTALL}/bin/init.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "${REINIT_BARRIER}/arrived"
for _ in $(seq 1 100); do
  [ "$(wc -l < "${REINIT_BARRIER}/arrived")" -ge "${REINIT_EXPECTED}" ] && exit 0
  sleep 0.1
done
exit 1
STUB
  _publish_release "g.txt" "release 1.2.0" "1.2.0"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  [ "$(wc -l < "${REINIT_BARRIER}/arrived")" -eq 3 ]
  [[ "${UPDATE_OUTPUT}" != *"reinit failed"* ]]
}

@test "a nested project is reinited after its ancestor, never beside it" {
  # A nested project's harness writes no plugin package its ancestor supplies,
  # so the ancestor must have written its own first: concurrent they both write
  # one and the host fails the duplicate plugin id.
  _new_sandbox "1.0.0:1.1.0"
  local parent="${SANDBOX}/parent" child="${SANDBOX}/parent/child"
  mkdir -p "${child}"
  # The child is listed first on purpose: the order must come from nesting.
  cat > "${INSTALL}/.devbot.global.jsonc" <<JSONC_EOF
{
  "gpu_enabled": false,
  "version": "",
  "projects": ["${child}", "${parent}"]
}
JSONC_EOF

  # The parent holds its turn long enough that a concurrent run always records
  # the child starting first; a wave run cannot produce that ordering at all.
  export REINIT_TRACE="${SANDBOX}/trace"
  cat > "${INSTALL}/bin/init.sh" <<'STUB'
#!/usr/bin/env bash
printf 'start %s\n' "$1" >> "${REINIT_TRACE}"
case "$1" in
  */child) ;;
  *) sleep 0.5 ;;
esac
printf 'end %s\n' "$1" >> "${REINIT_TRACE}"
STUB
  _publish_release "g.txt" "release 1.2.0" "1.2.0"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  local parent_end child_start
  parent_end="$(grep -nxF "end ${parent}" "${REINIT_TRACE}" | cut -d: -f1)"
  child_start="$(grep -nxF "start ${child}" "${REINIT_TRACE}" | cut -d: -f1)"
  [ -n "${parent_end}" ]
  [ -n "${child_start}" ]
  [ "${parent_end}" -lt "${child_start}" ]
}

@test "a failing project reinit is reported but does not abort the update" {
  _new_sandbox "1.0.0:1.1.0"
  local p1="${SANDBOX}/p1" p2="${SANDBOX}/p2"
  mkdir -p "${p1}" "${p2}"
  cat > "${INSTALL}/.devbot.global.jsonc" <<JSONC_EOF
{
  "gpu_enabled": false,
  "version": "",
  "projects": ["${p1}", "${p2}"]
}
JSONC_EOF
  export FAIL_PROJECT="${p1}"
  cat > "${INSTALL}/bin/init.sh" <<'STUB'
#!/usr/bin/env bash
[ "$1" = "${FAIL_PROJECT}" ] && exit 1
exit 0
STUB
  _publish_release "g.txt" "release 1.2.0" "1.2.0"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  [[ "${UPDATE_OUTPUT}" == *"reinit failed"* ]]
  # The new version is still recorded; only the reinit is reported.
  grep -q '"version": "1.2.0"' "${INSTALL}/.devbot.global.jsonc"
}
