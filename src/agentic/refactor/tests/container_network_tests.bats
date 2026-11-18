#!/usr/bin/env bats
# =============================================================================
# src/agentic/refactor/tests/container_network_tests.bats
# Every `docker run` these language plugins issue must state its network mode.
#
# The property: a container attached to the default bridge creates a veth pair,
# and the pair coming up (and going down) is a netlink link event. Chromium
# subscribes to RTMGRP_LINK, treats each fully-up link as a network change and
# aborts in-flight requests with ERR_NETWORK_CHANGED. These plugins spawn a
# container per call — one per Rector step, per rope/ts-morph operation — so a
# full test run churns the host's interfaces hard enough to break the developer's
# browser, which is what sent a whole session chasing a phantom GitHub outage.
#
# So: `--network none` where the engine needs no network (analysis), and
# `--network host` where it genuinely does (installing the engine), never the
# implicit bridge. Host networking also creates no veth pair.
#
# Measured on the affected machine: a bridge-attached one-shot container = 2
# `renamed from` events in the kernel log; the same container with
# `--network none` = 0.
# =============================================================================

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
  MODULE_DIR="$(cd "${TEST_DIR}/.." && pwd)"
  REPO_ROOT="$(cd "${MODULE_DIR}/../../.." && pwd)"
}

# Print "<file>:<line>\t<statement>" for every `docker run` the plugins issue.
#
# The statement is normalised before matching, because the same container is
# written three ways here and a scan that knew only the first would stay green
# while a real invocation lost its network flag:
#
#   printf ... | docker run --rm -i \        shell command, backslash-joined
#       --network none ...
#   argv = ["docker", "run", "--rm", ...]     tokenised argv in a python builder
#   "${container[@]}" | docker run ...        argv array expanded at call time
#
# So: join continuations, drop quotes, turn list commas into spaces, collapse
# whitespace, then search. The window after the match is bounded so one
# statement cannot borrow the next one's flags.
_docker_run_invocations() {
  python3 - "${REPO_ROOT}" <<'PY'
import glob, os, re, sys

root = sys.argv[1]
files = sorted(
    glob.glob(os.path.join(root, "src/agentic/refactor/langs/*/plugin.sh"))
    + glob.glob(os.path.join(root, "src/agentic/forensics/langs/*/plugin.sh"))
)
WINDOW = 400

for path in files:
    lines = open(path, encoding="utf-8").read().splitlines()
    i = 0
    while i < len(lines):
        start = i
        parts = []
        while i < len(lines):
            parts.append(lines[i])
            more = lines[i].rstrip().endswith("\\")
            i += 1
            if not more:
                break
        if lines[start].lstrip().startswith("#"):
            continue
        # One logical statement: continuations joined, quotes and list commas
        # gone, runs of whitespace collapsed — so the shell form, the tokenised
        # argv and the array expansion all read the same way.
        statement = " ".join(part.strip().rstrip("\\").strip() for part in parts)
        norm = statement.replace('"', "").replace("'", "").replace(",", " ")
        norm = re.sub(r"\s+", " ", norm).strip()
        at = norm.find("docker run")
        if at < 0:
            continue
        print(f"{os.path.relpath(path, root)}:{start + 1}\t{norm[at:at + WINDOW]}")
PY
}

@test "every language-plugin container states its network mode" {
  run _docker_run_invocations
  assert_success
  # Guard the scan itself: a renamed directory, or a rewrite that hides an
  # invocation, must not silently turn this green. Eight is the floor across the
  # four plugins that build a container (refactor php/py/ts, forensics php/ts).
  [ "$(printf '%s\n' "${output}" | grep -c 'docker run')" -ge 8 ] ||
    fail "the scan found implausibly few containers: ${output}"

  local bad=""
  while IFS=$'\t' read -r where command; do
    [[ -n "${where}" ]] || continue
    case "${command}" in
      *"--network none"* | *"--network host"* | *"--network=none"* | *"--network=host"*) ;;
      *) bad="${bad}${where}: ${command}"$'\n' ;;
    esac
  done <<<"${output}"

  [[ -z "${bad}" ]] || fail "containers left on the default bridge (veth churn):"$'\n'"${bad}"
}

@test "analysis runs are isolated, and only provisioning reaches the network" {
  run _docker_run_invocations
  assert_success

  local bad=""
  while IFS=$'\t' read -r where command; do
    [[ -n "${where}" ]] || continue
    # Installing an engine (composer require / npm install) genuinely needs the
    # network. Every other run — including a `composer php -r` version probe —
    # analyses or inspects and must be fully isolated.
    case "${command}" in
      *"composer:2 require"* | *"npm install"*)
        case "${command}" in
          *"--network host"* | *"--network=host"*) ;;
          *) bad="${bad}${where}: a network-needing run needs --network host: ${command}"$'\n' ;;
        esac
        ;;
      *)
        case "${command}" in
          *"--network none"* | *"--network=none"*) ;;
          *) bad="${bad}${where}: an analysis run needs --network none: ${command}"$'\n' ;;
        esac
        ;;
    esac
  done <<<"${output}"

  [[ -z "${bad}" ]] || fail "network mode does not match what the container does:"$'\n'"${bad}"
}
