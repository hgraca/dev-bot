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
  # sequential reinit would make the first stub time out and exit 1. The width
  # is pinned: the default scales with nproc, and a narrow runner fits two.
  export DEV_BOT_INIT_JOBS=3
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

@test "projects that are not nested run together whatever their depth" {
  # Depth orders ancestors before descendants; it is not a nesting test, so it
  # must not hold an unrelated project back behind a shallower one.
  _new_sandbox "1.0.0:1.1.0"
  local shallow="${SANDBOX}/shallow" deep="${SANDBOX}/group/deep"
  mkdir -p "${shallow}" "${deep}"
  cat > "${INSTALL}/.devbot.global.jsonc" <<JSONC_EOF
{
  "gpu_enabled": false,
  "version": "",
  "projects": ["${shallow}", "${deep}"]
}
JSONC_EOF

  export REINIT_TRACE="${SANDBOX}/trace"
  cat > "${INSTALL}/bin/init.sh" <<'STUB'
#!/usr/bin/env bash
printf 'start %s\n' "$1" >> "${REINIT_TRACE}"
case "$1" in
  */shallow) sleep 0.5 ;;
esac
printf 'end %s\n' "$1" >> "${REINIT_TRACE}"
STUB
  _publish_release "g.txt" "release 1.2.0" "1.2.0"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  local shallow_end deep_start
  shallow_end="$(grep -nxF "end ${shallow}" "${REINIT_TRACE}" | cut -d: -f1)"
  deep_start="$(grep -nxF "start ${deep}" "${REINIT_TRACE}" | cut -d: -f1)"
  [ -n "$shallow_end" ]
  [ -n "$deep_start" ]
  [ "$deep_start" -lt "$shallow_end" ]
}

@test "a nested project starts when its own ancestor ends, not another's" {
  # Reaping the oldest launch holds a descendant behind unrelated work that
  # happens to have started earlier.
  _new_sandbox "1.0.0:1.1.0"
  local slow="${SANDBOX}/slow" parent="${SANDBOX}/group/parent" child="${SANDBOX}/group/parent/child"
  mkdir -p "${slow}" "${parent}" "${child}"
  cat > "${INSTALL}/.devbot.global.jsonc" <<JSONC_EOF
{
  "gpu_enabled": false,
  "version": "",
  "projects": ["${slow}", "${parent}", "${child}"]
}
JSONC_EOF

  export REINIT_TRACE="${SANDBOX}/trace"
  cat > "${INSTALL}/bin/init.sh" <<'STUB'
#!/usr/bin/env bash
printf 'start %s\n' "$1" >> "${REINIT_TRACE}"
case "$1" in
  */slow) sleep 1 ;;
esac
printf 'end %s\n' "$1" >> "${REINIT_TRACE}"
STUB
  _publish_release "g.txt" "release 1.2.0" "1.2.0"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  local slow_end child_start
  slow_end="$(grep -nxF "end ${slow}" "${REINIT_TRACE}" | cut -d: -f1)"
  child_start="$(grep -nxF "start ${child}" "${REINIT_TRACE}" | cut -d: -f1)"
  [ -n "$slow_end" ]
  [ -n "$child_start" ]
  [ "$child_start" -lt "$slow_end" ]
}

@test "reinit stops at the configured number of concurrent projects" {
  # update has no -j, but it must not spawn every registered project at once:
  # DEV_BOT_INIT_JOBS is the knob init --all already honours.
  _new_sandbox "1.0.0:1.1.0"
  local p1="${SANDBOX}/p1" p2="${SANDBOX}/p2" p3="${SANDBOX}/p3" p4="${SANDBOX}/p4"
  mkdir -p "${p1}" "${p2}" "${p3}" "${p4}"
  cat > "${INSTALL}/.devbot.global.jsonc" <<JSONC_EOF
{
  "gpu_enabled": false,
  "version": "",
  "projects": ["${p1}", "${p2}", "${p3}", "${p4}"]
}
JSONC_EOF

  export REINIT_TRACE="${SANDBOX}/trace"
  cat > "${INSTALL}/bin/init.sh" <<'STUB'
#!/usr/bin/env bash
printf 'start %s\n' "$1" >> "${REINIT_TRACE}"
sleep 0.4
printf 'end %s\n' "$1" >> "${REINIT_TRACE}"
STUB
  export DEV_BOT_INIT_JOBS=2
  _publish_release "g.txt" "release 1.2.0" "1.2.0"

  _run_update
  unset DEV_BOT_INIT_JOBS

  [ "$UPDATE_STATUS" -eq 0 ]
  local line running=0 peak=0
  while IFS= read -r line; do
    case "${line}" in
      start*) running=$(( running + 1 )) ;;
      end*) running=$(( running - 1 )) ;;
    esac
    if [[ ${running} -gt ${peak} ]]; then peak=${running}; fi
  done < "${REINIT_TRACE}"
  [ "${peak}" -eq 2 ]
}

@test "a project reached through a symlink still waits for its ancestor" {
  # registries keep the spelling they were given; the child may be listed
  # through a link, which a lexical comparison cannot see as nested.
  _new_sandbox "1.0.0:1.1.0"
  local real="${SANDBOX}/real/parent" link="${SANDBOX}/link"
  mkdir -p "${real}/child"
  ln -s "${real}" "${link}"
  cat > "${INSTALL}/.devbot.global.jsonc" <<JSONC_EOF
{
  "gpu_enabled": false,
  "version": "",
  "projects": ["${real}", "${link}/child"]
}
JSONC_EOF

  export REINIT_TRACE="${SANDBOX}/trace"
  cat > "${INSTALL}/bin/init.sh" <<'STUB'
#!/usr/bin/env bash
printf 'start %s\n' "$1" >> "${REINIT_TRACE}"
case "$1" in
  */parent) sleep 0.5 ;;
esac
printf 'end %s\n' "$1" >> "${REINIT_TRACE}"
STUB
  _publish_release "g.txt" "release 1.2.0" "1.2.0"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  local parent_end child_start
  parent_end="$(grep -nxF "end ${real}" "${REINIT_TRACE}" | cut -d: -f1)"
  child_start="$(grep -nxF "start ${real}/child" "${REINIT_TRACE}" | cut -d: -f1)"
  [ -n "$parent_end" ]
  [ -n "$child_start" ]
  [ "$parent_end" -lt "$child_start" ]
}

@test "one physical project is reinited once however it is spelled" {
  # Canonicalising the paths makes the two spellings equal, so the scheduler
  # would run two inits over the same tree unless they are deduplicated.
  _new_sandbox "1.0.0:1.1.0"
  local real="${SANDBOX}/real/parent" link="${SANDBOX}/link"
  mkdir -p "${real}"
  ln -s "${real}" "${link}"
  cat > "${INSTALL}/.devbot.global.jsonc" <<JSONC_EOF
{
  "gpu_enabled": false,
  "version": "",
  "projects": ["${real}", "${link}"]
}
JSONC_EOF

  export REINIT_TRACE="${SANDBOX}/trace"
  cat > "${INSTALL}/bin/init.sh" <<'STUB'
#!/usr/bin/env bash
printf 'start %s\n' "$1" >> "${REINIT_TRACE}"
STUB
  _publish_release "g.txt" "release 1.2.0" "1.2.0"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  [ "$(grep -c '^start ' "${REINIT_TRACE}")" -eq 1 ]
}
