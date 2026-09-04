#!/usr/bin/env bats

# src/agentic/k8s/tests/lint-k8s_tests.bats
# Directory-sweep scope for lint-k8s (audit-48 N5): a sweep over a directory
# previously gathered EVERY .yml/.yaml/.json file and kubeconform-validated
# each as a Kubernetes manifest — non-manifests (config files, editor/tool
# caches such as .opencode/index/*.json, graphify-out) produced a
# "failed validation: missing 'kind' key" error per file, burying the real
# findings. Sweeps now gather only manifest-looking files (contain an
# apiVersion key and a kind key); an explicitly-passed file is still linted
# as-is so a mistaken target stays loud.

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  MODULE_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  TOOL="$MODULE_DIR/tools/lint-k8s/lint-k8s.mcp.sh"

  if ! command -v kubeconform >/dev/null 2>&1 || ! command -v kube-linter >/dev/null 2>&1; then
    skip "kubeconform/kube-linter not installed"
  fi

  # Run the tool from a per-test scratch dir so any stray side effect (e.g. a
  # kube-linter output file) stays confined and never lands in the repo.
  cd "$BATS_TEST_TMPDIR"
}

# A directory with one valid ConfigMap next to non-manifest noise files.
make_fixture() {
  local dir="$1"
  mkdir -p "$dir"
  printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: demo\n' > "$dir/manifest.yml"
  printf 'not: a\nmanifest: here\n' > "$dir/noise.yml"
  printf '{"a": 1}\n' > "$dir/cache.json"
}

@test "directory sweep ignores non-manifest YAML/JSON (text format)" {
  local dir="$BATS_TEST_TMPDIR/project"
  make_fixture "$dir"

  run bash "$TOOL" "$dir"
  assert_success
  # The one real manifest validated — "All valid" only prints when no file
  # failed kubeconform.
  assert_output --partial "All valid"
  # The non-manifest files must not be gathered or reported.
  refute_output --partial "noise.yml"
  refute_output --partial "cache.json"
}

@test "directory sweep reports valid in JSON format when only the manifest is gathered" {
  local dir="$BATS_TEST_TMPDIR/project"
  make_fixture "$dir"

  run bash "$TOOL" --json "$dir"
  assert_success
  assert_output --partial '"valid": true'
  # kube-linter's report is embedded as real JSON (--format json on stdout) —
  # not written to a stray output file (kube-linter's --output is a file path).
  assert_output --partial '"Reports"'
  # The whole payload must parse as JSON (guards the trailing-comma class).
  printf '%s' "$output" > "$BATS_TEST_TMPDIR/report.json"
  run python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$BATS_TEST_TMPDIR/report.json"
  assert_success
}

@test "json mode creates no stray output file in the working directory" {
  local dir="$BATS_TEST_TMPDIR/project"
  make_fixture "$dir"

  run bash "$TOOL" --json "$dir"
  assert_success
  refute [ -e "$BATS_TEST_TMPDIR/json" ]
}

@test "an explicitly-passed non-manifest file is still linted loudly" {
  local file="$BATS_TEST_TMPDIR/noise.yml"
  printf 'not: a\nmanifest: here\n' > "$file"

  run bash "$TOOL" "$file"
  assert_success
  # Explicit target: the file is reported (not silently skipped).
  assert_output --partial "noise.yml"
  refute_output --partial "All valid"
}

@test "a directory with no manifests reports none found" {
  local dir="$BATS_TEST_TMPDIR/empty"
  mkdir -p "$dir"
  printf 'just: config\n' > "$dir/config.yml"

  run bash "$TOOL" "$dir"
  assert_failure
  assert_output --partial "no Kubernetes manifests found"
}

@test "the --schema override is passed through to kubeconform" {
  local dir="$BATS_TEST_TMPDIR/project"
  make_fixture "$dir"

  # A bogus schema location makes kubeconform fail validation — proves the
  # parsed --schema flag actually reaches kubeconform (-schema-location),
  # rather than being parsed and silently dropped (shellcheck SC2034).
  run bash "$TOOL" --schema /nonexistent/schemas "$dir"
  assert_success
  refute_output --partial "All valid"
}
