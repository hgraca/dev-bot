#!/usr/bin/env bats
# =============================================================================
# bin/tests/update_release_notes_tests.bats
# bin/update.sh — the release-notes section printed at the end of a move.
# A release carries its notes as the annotated tag message (tag.sh publishes
# release.v<VERSION>.no-vcs.md with `git tag -a -F`), so the section is built
# from the tags between the version being left and the version being landed on.
#
# Fixtures live in update_helpers.bash (_publish_release takes an optional
# notes argument that creates an annotated tag).
# =============================================================================

load update_helpers

setup_file() { _update_file_setup; }
setup() { _update_setup; }
teardown() { _update_teardown; }

NOTES_110=$'# Release v1.1.0\n\n- one-one landed\n'
NOTES_1_10=$'# Release v1.10.0\n\n- one-ten landed\n'
NOTES_111=$'# Release v1.11.0\n\n- one-eleven landed\n'
NOTES_120=$'# Release v1.2.0\n\n- one-two landed\n'

@test "release notes: prints every crossed version, oldest first" {
  _new_sandbox "1.0.0"
  _publish_release g.txt "release 1.1.0" "1.1.0" "${NOTES_110}"
  _publish_release h.txt "release 1.2.0" "1.2.0" "${NOTES_120}"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  [[ "$UPDATE_OUTPUT" == *"Release Notes"* ]]
  [[ "$UPDATE_OUTPUT" == *"- one-one landed"* ]]
  [[ "$UPDATE_OUTPUT" == *"- one-two landed"* ]]
  # Chronological: the older release's notes come first.
  [[ "$UPDATE_OUTPUT" == *"# Release v1.1.0"*"# Release v1.2.0"* ]]
}

@test "release notes: excludes the version being updated from" {
  _new_sandbox "1.0.0"
  _publish_release g.txt "release 1.1.0" "1.1.0" "${NOTES_110}"
  _checkout_install_tag "1.1.0"
  _publish_release h.txt "release 1.2.0" "1.2.0" "${NOTES_120}"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  [[ "$UPDATE_OUTPUT" == *"- one-two landed"* ]]
  [[ "$UPDATE_OUTPUT" != *"- one-one landed"* ]]
}

@test "release notes: a tag without notes is marked, and does not stop the rest" {
  _new_sandbox "1.0.0"
  # Lightweight tag: its message is the commit subject, not release notes.
  _publish_release g.txt "release 1.1.0" "1.1.0"
  _publish_release h.txt "release 1.2.0" "1.2.0" "${NOTES_120}"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  [[ "$UPDATE_OUTPUT" == *"1.1.0 — no release notes recorded"* ]]
  [[ "$UPDATE_OUTPUT" == *"- one-two landed"* ]]
}

@test "release notes: --auto prints the section too" {
  _new_sandbox "1.0.0"
  _publish_release g.txt "release 1.1.0" "1.1.0" "${NOTES_110}"

  _run_update --auto

  [ "$UPDATE_STATUS" -eq 0 ]
  [[ "$UPDATE_OUTPUT" == *"Release Notes"* ]]
  [[ "$UPDATE_OUTPUT" == *"- one-one landed"* ]]
}

@test "release notes: a downgrade prints only the target's notes" {
  _new_sandbox "1.0.0"
  _publish_release g.txt "release 1.1.0" "1.1.0" "${NOTES_110}"
  _publish_release h.txt "release 1.2.0" "1.2.0" "${NOTES_120}"
  _checkout_install_tag "1.2.0"

  _run_update "1.1.0"

  [ "$UPDATE_STATUS" -eq 0 ]
  [[ "$UPDATE_OUTPUT" == *"- one-one landed"* ]]
  [[ "$UPDATE_OUTPUT" != *"- one-two landed"* ]]
}

@test "release notes: nothing moves, nothing is printed" {
  _new_sandbox "1.0.0:1.1.0"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  [[ "$UPDATE_OUTPUT" == *"Already on the latest version (1.1.0)"* ]]
  [[ "$UPDATE_OUTPUT" != *"Release Notes"* ]]
}

@test "release notes: version order holds across a multi-digit minor" {
  _new_sandbox "1.9.0"
  _publish_release g.txt "release 1.10.0" "1.10.0" "${NOTES_1_10}"
  _publish_release h.txt "release 1.11.0" "1.11.0" "${NOTES_111}"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  # Plain refname order would sort 1.10.0/1.11.0/1.9.0 and slice both away.
  [[ "$UPDATE_OUTPUT" == *"# Release v1.10.0"*"# Release v1.11.0"* ]]
}

@test "release notes: an untagged source shows the target only, and says so" {
  # No tags anywhere: _describe_head falls back to a short sha, so the range
  # cannot be anchored and the section must degrade visibly.
  _new_sandbox ""
  _publish_release h.txt "release 1.2.0" "1.2.0" "${NOTES_120}"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  [[ "$UPDATE_OUTPUT" == *"- one-two landed"* ]]
  [[ "$UPDATE_OUTPUT" == *"not a release tag — showing 1.2.0 only"* ]]
}

@test "release notes: non-release tags inside the range are not listed" {
  _new_sandbox "1.0.0"
  _publish_release g.txt "release 1.1.0" "1.1.0" "${NOTES_110}"
  # Both sort between 1.1.0 and 1.2.0, and neither is a release shape:
  # a pre-release, and four components on a non-zero major.
  git -C "${ORIGIN}" tag "1.1.0-rc1"
  git -C "${ORIGIN}" tag "1.1.0.1"
  _publish_release h.txt "release 1.2.0" "1.2.0" "${NOTES_120}"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  # No marker row for the rc tag — the fetch prints its name, the section does not.
  [[ "$UPDATE_OUTPUT" != *"no release notes recorded"* ]]
  [[ "$UPDATE_OUTPUT" == *"- one-two landed"* ]]
}

@test "release notes: a lightweight tag is never read as a release file" {
  _new_sandbox "1.0.0"
  _publish_release g.txt "release 1.2.0" "1.2.0" "${NOTES_120}"
  # Lightweight tag on a commit whose message mimics a release heading.
  git -C "${ORIGIN}" checkout -q main
  git -C "${ORIGIN}" commit -q --allow-empty -m "# Release v1.3.0"
  git -C "${ORIGIN}" tag "1.3.0"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  [[ "$UPDATE_OUTPUT" == *"1.3.0 — no release notes recorded"* ]]
  [[ "$UPDATE_OUTPUT" == *"- one-two landed"* ]]
}

@test "release notes: the section closes the run, after the summary" {
  _new_sandbox "1.0.0"
  _publish_release g.txt "release 1.1.0" "1.1.0" "${NOTES_110}"

  _run_update

  [ "$UPDATE_STATUS" -eq 0 ]
  [[ "$UPDATE_OUTPUT" == *"DevBot update complete"*"Release Notes"*"Total:"* ]]
}
