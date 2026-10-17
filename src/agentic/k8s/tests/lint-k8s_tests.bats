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

@test "a CRD without a bundled schema is skipped, not failed" {
  local dir="$BATS_TEST_TMPDIR/crd"
  mkdir -p "$dir"
  printf 'apiVersion: example.com/v1\nkind: Widget\nmetadata:\n  name: demo\n' > "$dir/widget.yml"

  run bash "$TOOL" "$dir"

  assert_success
  assert_output --partial "Skipped: 1"
  assert_output --partial "All valid"
}

@test "--changed lints only manifests changed against the base ref" {
  local dir="$BATS_TEST_TMPDIR/changed"
  mkdir -p "$dir"
  git -C "$dir" init --initial-branch=main >/dev/null 2>&1
  git -C "$dir" config user.email "test@test.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" config commit.gpgsign false
  printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: first\n' > "$dir/first.yml"
  printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: second\n' > "$dir/second.yml"
  git -C "$dir" add -A && git -C "$dir" commit -m initial >/dev/null 2>&1
  printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: second\n  labels:\n    changed: "yes"\n' > "$dir/second.yml"

  run bash "$TOOL" --json --changed "$dir"

  assert_success
  assert_output --partial '"files": 1'
  assert_output --partial '"changed": true'
}

@test "--changed reports no work when nothing changed" {
  local dir="$BATS_TEST_TMPDIR/unchanged"
  mkdir -p "$dir"
  git -C "$dir" init --initial-branch=main >/dev/null 2>&1
  git -C "$dir" config user.email "test@test.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" config commit.gpgsign false
  printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: demo\n' > "$dir/manifest.yml"
  git -C "$dir" add -A && git -C "$dir" commit -m initial >/dev/null 2>&1

  run bash "$TOOL" --changed "$dir"

  assert_success
  assert_output --partial "no changed Kubernetes manifests"
}

@test "--changed works with a relative target" {
  local dir="$BATS_TEST_TMPDIR/changed-relative"
  mkdir -p "$dir"
  git -C "$dir" init --initial-branch=main >/dev/null 2>&1
  git -C "$dir" config user.email "test@test.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" config commit.gpgsign false
  printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: first\n' > "$dir/first.yml"
  printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: second\n' > "$dir/second.yml"
  git -C "$dir" add -A && git -C "$dir" commit -m initial >/dev/null 2>&1
  printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: second\n  labels:\n    changed: "yes"\n' > "$dir/second.yml"

  cd "$dir"
  run bash "$TOOL" --json --changed .

  assert_success
  assert_output --partial '"files": 1'
}

@test "--changed resolves a .. target from a subdirectory" {
  local dir="$BATS_TEST_TMPDIR/changed-subdir"
  mkdir -p "$dir/sub"
  git -C "$dir" init --initial-branch=main >/dev/null 2>&1
  git -C "$dir" config user.email "test@test.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" config commit.gpgsign false
  printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: demo\n' > "$dir/manifest.yml"
  git -C "$dir" add -A && git -C "$dir" commit -m initial >/dev/null 2>&1
  printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: demo\n  labels:\n    changed: "yes"\n' > "$dir/manifest.yml"

  cd "$dir/sub"
  run bash "$TOOL" --json --changed ..

  assert_success
  assert_output --partial '"files": 1'
}

@test "--changed rejects a base ref that does not name a commit" {
  local dir="$BATS_TEST_TMPDIR/changed-bad-base"
  mkdir -p "$dir"
  git -C "$dir" init --initial-branch=main >/dev/null 2>&1
  git -C "$dir" config user.email "test@test.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" config commit.gpgsign false
  printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: demo\n' > "$dir/manifest.yml"
  git -C "$dir" add -A && git -C "$dir" commit -m initial >/dev/null 2>&1

  run bash "$TOOL" --changed --base not-a-ref "$dir"

  assert_failure
  assert_output --partial "does not name a commit"
}

@test "--changed options may follow the positional target" {
  local dir="$BATS_TEST_TMPDIR/changed-path-first"
  mkdir -p "$dir"
  git -C "$dir" init --initial-branch=main >/dev/null 2>&1
  git -C "$dir" config user.email "test@test.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" config commit.gpgsign false
  printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: demo\n' > "$dir/manifest.yml"
  git -C "$dir" add -A && git -C "$dir" commit -m initial >/dev/null 2>&1
  printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: demo\n  labels:\n    changed: "yes"\n' > "$dir/manifest.yml"

  run bash "$TOOL" "$dir" --json --changed

  assert_success
  assert_output --partial '"files": 1'
}

@test "--json --changed with no changes returns a valid empty report" {
  local dir="$BATS_TEST_TMPDIR/changed-clean-json"
  mkdir -p "$dir"
  git -C "$dir" init --initial-branch=main >/dev/null 2>&1
  git -C "$dir" config user.email "test@test.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" config commit.gpgsign false
  printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: demo\n' > "$dir/manifest.yml"
  git -C "$dir" add -A && git -C "$dir" commit -m initial >/dev/null 2>&1

  run bash "$TOOL" --json --changed "$dir"

  assert_success
  assert_output --partial '"files":0'
  assert_output --partial '"changed":true'
}
