#!/usr/bin/env bats
# =============================================================================
# src/agentic/security/tests/findings_tests.bats
# Contract for the findings store and the gate: states, verdicts, exit codes and
# the fail-closed rule. Every test drives a real diff through the gate rather
# than asserting on prose.
# =============================================================================

setup() {
    bats_load_library bats-support
    bats_load_library bats-assert

    MODULE="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    FINDINGS="${MODULE}/scripts/findings.sh"
    REPO="${BATS_TEST_TMPDIR}/repo"
    export SEC_FINDINGS_STORE="${BATS_TEST_TMPDIR}/findings.jsonl"

    mkdir -p "${REPO}/app"
    git -C "${REPO}" init -q
    git -C "${REPO}" config user.email tester@example.invalid
    git -C "${REPO}" config user.name tester

    cat >"${REPO}/app/InvoiceController.php" <<'PHP'
<?php
class InvoiceController {
    public function show($id) {
        return Invoice::findOrFail($id);
    }
}
PHP

    cat >"${REPO}/app/Caller.php" <<'PHP'
<?php
function render($c, $id) {
    return $c->show($id);
}
PHP

    git -C "${REPO}" add -A
    git -C "${REPO}" commit -qm "initial"
    HEAD_SHA="$(git -C "${REPO}" rev-parse HEAD)"
}

# seed <status> <severity> <file> <line> <discovered>
seed() {
    local status="${1:-confirmed}" severity="${2:-High}"
    local file="${3:-app/InvoiceController.php}" line="${4:-3}"
    local discovered="${5:-${HEAD_SHA}}"
    cat >"${SEC_FINDINGS_STORE}" <<JSON
{"id":"SEC-1","title":"Object read by id without a tenant check","severity":"${severity}","status":"${status}","tier":"read-in-source","discovered":"${discovered}","location":{"file":"${file}","line":${line},"symbol":"InvoiceController::show"}}
JSON
}

diff_on_own_lines() {
    cat <<'DIFF'
diff --git a/app/InvoiceController.php b/app/InvoiceController.php
--- a/app/InvoiceController.php
+++ b/app/InvoiceController.php
@@ -3,0 +4,1 @@
+        return null;
DIFF
}

diff_elsewhere_in_file() {
    cat <<'DIFF'
diff --git a/app/InvoiceController.php b/app/InvoiceController.php
--- a/app/InvoiceController.php
+++ b/app/InvoiceController.php
@@ -40,0 +41,1 @@
+        return null;
DIFF
}

diff_in_caller() {
    cat <<'DIFF'
diff --git a/app/Caller.php b/app/Caller.php
--- a/app/Caller.php
+++ b/app/Caller.php
@@ -2,0 +3,1 @@
+    log_call();
DIFF
}

# --- store ------------------------------------------------------------------

@test "the wrapper and implementation parse" {
    run bash -n "${FINDINGS}"
    assert_success
    run python3 -m py_compile "${MODULE}/scripts/findings.py"
    assert_success
}

@test "add records a valid finding, and check reports it" {
    run bash "${FINDINGS}" add <<'JSON'
{"id":"SEC-1","title":"t","severity":"High","status":"open","tier":"observed","discovered":"abc1234"}
JSON
    assert_success
    assert_output --partial "recorded SEC-1"
    run bash "${FINDINGS}" check
    assert_success
    assert_output --partial "1 record(s)"
}

@test "add refuses a record missing a required field" {
    run bash "${FINDINGS}" add <<'JSON'
{"id":"SEC-1","title":"t","severity":"High"}
JSON
    assert_failure 2
    assert_output --partial "missing status"
}

@test "add refuses a record with no commit to bind it to" {
    # Without `discovered` the verdict can never go stale, so it is required.
    run bash "${FINDINGS}" add <<'JSON'
{"id":"SEC-1","title":"t","severity":"High","status":"open","tier":"observed"}
JSON
    assert_failure 2
    assert_output --partial "missing discovered"
}

@test "add refuses an array instead of an object" {
    run bash "${FINDINGS}" add <<'JSON'
[{"id":"SEC-1"}]
JSON
    assert_failure 3
    assert_output --partial "one JSON object"
}

@test "a source location without a line is rejected" {
    # A record with no line can never match a hunk, so it would classify as
    # unrelated forever and a High finding would never block.
    run bash "${FINDINGS}" add <<'JSON'
{"id":"SEC-1","title":"t","severity":"High","status":"open","tier":"observed","discovered":"abc","location":{"file":"app/x.php"}}
JSON
    assert_failure 2
    assert_output --partial "positive integer line"
}

@test "update replaces a record so a re-test can persist its verdict" {
    seed confirmed High app/InvoiceController.php 3
    run bash "${FINDINGS}" update <<'JSON'
{"id":"SEC-1","title":"Object read by id without a tenant check","severity":"High","status":"mitigated","tier":"read-in-source","discovered":"abc1234","location":{"file":"app/InvoiceController.php","line":3,"symbol":"InvoiceController::show"}}
JSON
    assert_success
    assert_output --partial "updated SEC-1"
    run bash "${FINDINGS}" list --status mitigated
    assert_output --partial "SEC-1"
    # Replacing, not appending: the old open record must be gone.
    run bash "${FINDINGS}" check
    assert_output --partial "1 record(s)"
}

@test "update refuses an id the store does not hold" {
    seed confirmed High app/InvoiceController.php 3
    run bash "${FINDINGS}" update <<'JSON'
{"id":"SEC-99","title":"t","severity":"High","status":"open","tier":"observed","discovered":"abc"}
JSON
    assert_failure 2
    assert_output --partial "not in the store"
}

@test "a non-string discovered is rejected" {
    # is_stale() calls .strip() on it, so a wrong type crashes the gate instead
    # of returning the documented REVIEW.
    run bash "${FINDINGS}" add <<'JSON'
{"id":"SEC-1","title":"t","severity":"High","status":"open","tier":"observed","discovered":123}
JSON
    assert_failure 2
    assert_output --partial "discovered is not a string"
}

@test "add refuses a duplicate id" {
    run bash "${FINDINGS}" add <<'JSON'
{"id":"SEC-1","title":"t","severity":"High","status":"open","tier":"observed","discovered":"abc1234"}
JSON
    assert_success
    run bash "${FINDINGS}" add <<'JSON'
{"id":"SEC-1","title":"again","severity":"Low","status":"open","tier":"observed","discovered":"abc1234"}
JSON
    assert_failure 2
    assert_output --partial "already in the store"
}

@test "check fails on a severity outside the bands" {
    cat >"${SEC_FINDINGS_STORE}" <<'JSON'
{"id":"SEC-9","title":"t","severity":"Severe","status":"open","tier":"observed"}
JSON
    run bash "${FINDINGS}" check
    assert_failure 1
    assert_output --partial "not one of"
}

@test "list filters by file" {
    seed confirmed High app/InvoiceController.php 3
    run bash "${FINDINGS}" list --file app/InvoiceController.php
    assert_success
    assert_output --partial "SEC-1"
    run bash "${FINDINGS}" list --file app/Other.php
    assert_success
    assert_output --partial "no matching findings"
}

# --- gate -------------------------------------------------------------------
#
# `run` must be invoked in the test body: a helper called inside a pipeline runs
# in a subshell, and the captured $output/$status never reach the assertion.

@test "gate blocks a High finding on the changed lines" {
    seed confirmed High app/InvoiceController.php 3
    diff_on_own_lines >"${BATS_TEST_TMPDIR}/d.diff"
    run bash "${FINDINGS}" --store "${SEC_FINDINGS_STORE}" gate --repo "${REPO}" \
        <"${BATS_TEST_TMPDIR}/d.diff"
    assert_failure 2
    assert_output --partial "BLOCK"
    assert_output --partial "direct"
}

@test "gate reviews a finding elsewhere in a changed file" {
    seed confirmed High app/InvoiceController.php 3
    diff_elsewhere_in_file >"${BATS_TEST_TMPDIR}/d.diff"
    run bash "${FINDINGS}" --store "${SEC_FINDINGS_STORE}" gate --repo "${REPO}" \
        <"${BATS_TEST_TMPDIR}/d.diff"
    assert_failure 1
    assert_output --partial "unrelated_in_file"
}

@test "gate reviews when a changed file calls the finding's symbol" {
    # The finding sits in InvoiceController; the change is in a file that calls it.
    seed confirmed High app/InvoiceController.php 3
    diff_in_caller >"${BATS_TEST_TMPDIR}/d.diff"
    run bash "${FINDINGS}" --store "${SEC_FINDINGS_STORE}" gate --repo "${REPO}" \
        <"${BATS_TEST_TMPDIR}/d.diff"
    assert_failure 1
    assert_output --partial "caller_radius"
}

@test "gate passes when nothing known intersects the change" {
    seed confirmed High app/InvoiceController.php 3
    cat >"${BATS_TEST_TMPDIR}/d.diff" <<'DIFF'
diff --git a/app/Unrelated.php b/app/Unrelated.php
--- a/app/Unrelated.php
+++ b/app/Unrelated.php
@@ -1,0 +2,1 @@
+<?php
DIFF
    run bash "${FINDINGS}" --store "${SEC_FINDINGS_STORE}" gate --repo "${REPO}" \
        <"${BATS_TEST_TMPDIR}/d.diff"
    assert_success
    assert_output --partial "PASS"
}

@test "a lower severity is a review, not a block" {
    seed confirmed Medium app/InvoiceController.php 3
    diff_on_own_lines >"${BATS_TEST_TMPDIR}/d.diff"
    run bash "${FINDINGS}" --store "${SEC_FINDINGS_STORE}" gate --repo "${REPO}" \
        <"${BATS_TEST_TMPDIR}/d.diff"
    assert_failure 1
    assert_output --partial "REVIEW"
}

@test "a closed finding does not gate" {
    seed false_positive High app/InvoiceController.php 3
    diff_on_own_lines >"${BATS_TEST_TMPDIR}/d.diff"
    run bash "${FINDINGS}" --store "${SEC_FINDINGS_STORE}" gate --repo "${REPO}" \
        <"${BATS_TEST_TMPDIR}/d.diff"
    assert_success
    assert_output --partial "PASS"
}

@test "gate fails closed when there is no store" {
    rm -f "${SEC_FINDINGS_STORE}"
    diff_on_own_lines >"${BATS_TEST_TMPDIR}/d.diff"
    run bash "${FINDINGS}" --store "${SEC_FINDINGS_STORE}" gate --repo "${REPO}" \
        <"${BATS_TEST_TMPDIR}/d.diff"
    assert_failure 1
    assert_output --partial "no findings store"
}

@test "gate fails closed on an unreadable store" {
    printf '{not json}\n' >"${SEC_FINDINGS_STORE}"
    diff_on_own_lines >"${BATS_TEST_TMPDIR}/d.diff"
    run bash "${FINDINGS}" --store "${SEC_FINDINGS_STORE}" gate --repo "${REPO}" \
        <"${BATS_TEST_TMPDIR}/d.diff"
    assert_failure 1
    assert_output --partial "cannot be read"
}

@test "gate fails closed on a store that does not validate" {
    # Syntactically valid, semantically meaningless: answering PASS here would be
    # the gate clearing a record it never understood.
    cat >"${SEC_FINDINGS_STORE}" <<'JSON'
{"id":"SEC-9","title":"t","severity":"Severe","status":"open","tier":"observed","discovered":"abc"}
JSON
    diff_on_own_lines >"${BATS_TEST_TMPDIR}/d.diff"
    run bash "${FINDINGS}" --store "${SEC_FINDINGS_STORE}" gate --repo "${REPO}" \
        <"${BATS_TEST_TMPDIR}/d.diff"
    assert_failure 1
    assert_output --partial "does not validate"
}

@test "gate sees a deletion-only hunk" {
    # A deletion has no new-side lines; dropping it made a real change look like
    # an empty change set, so a finding on the deleted line was never matched.
    seed confirmed High app/InvoiceController.php 4
    cat >"${BATS_TEST_TMPDIR}/d.diff" <<'DIFF'
diff --git a/app/InvoiceController.php b/app/InvoiceController.php
--- a/app/InvoiceController.php
+++ b/app/InvoiceController.php
@@ -4,1 +3,0 @@
-        return Invoice::findOrFail($id);
DIFF
    run bash "${FINDINGS}" --store "${SEC_FINDINGS_STORE}" gate --repo "${REPO}" \
        <"${BATS_TEST_TMPDIR}/d.diff"
    assert_failure 2
    assert_output --partial "direct"
}

@test "gate sees a whole-file deletion" {
    # `+++ /dev/null` used to clear the path, so the file vanished from the diff.
    seed confirmed High app/InvoiceController.php 3
    cat >"${BATS_TEST_TMPDIR}/d.diff" <<'DIFF'
diff --git a/app/InvoiceController.php b/app/InvoiceController.php
deleted file mode 100644
--- a/app/InvoiceController.php
+++ /dev/null
@@ -1,6 +0,0 @@
-<?php
-class InvoiceController {
-    public function show($id) {
-        return Invoice::findOrFail($id);
-    }
-}
DIFF
    run bash "${FINDINGS}" --store "${SEC_FINDINGS_STORE}" gate --repo "${REPO}" \
        <"${BATS_TEST_TMPDIR}/d.diff"
    assert_failure 2
    assert_output --partial "direct"
}

@test "a multi-line deletion matches a line away from the anchor" {
    # The old-side range is what a finding's line number refers to here.
    seed confirmed High app/InvoiceController.php 5
    cat >"${BATS_TEST_TMPDIR}/d.diff" <<'DIFF'
diff --git a/app/InvoiceController.php b/app/InvoiceController.php
--- a/app/InvoiceController.php
+++ b/app/InvoiceController.php
@@ -2,5 +1,0 @@
-class InvoiceController {
-    public function show($id) {
-        return Invoice::findOrFail($id);
-    }
DIFF
    run bash "${FINDINGS}" --store "${SEC_FINDINGS_STORE}" gate --repo "${REPO}" \
        <"${BATS_TEST_TMPDIR}/d.diff"
    assert_failure 2
    assert_output --partial "direct"
}

@test "a payload line that looks like a header does not corrupt the next file" {
    # A deleted source line `-- a/decoy` renders as `--- a/decoy` inside the
    # hunk. Parsed as a header it starts a phantom file and breaks attribution.
    seed confirmed High app/Other.php 11
    cat >"${BATS_TEST_TMPDIR}/d.diff" <<'DIFF'
diff --git a/app/InvoiceController.php b/app/InvoiceController.php
--- a/app/InvoiceController.php
+++ b/app/InvoiceController.php
@@ -3,1 +3,2 @@
--- a/decoy
+    // replaced
+    // twice
diff --git a/app/Other.php b/app/Other.php
--- a/app/Other.php
+++ b/app/Other.php
@@ -10,0 +11,1 @@
+<?php
DIFF
    run bash "${FINDINGS}" --store "${SEC_FINDINGS_STORE}" gate --repo "${REPO}" \
        <"${BATS_TEST_TMPDIR}/d.diff"
    assert_failure 2
    assert_output --partial "direct"
}

@test "a finding under the pre-rename path is reviewed, not passed" {
    seed confirmed High app/OldName.php 3
    cat >"${BATS_TEST_TMPDIR}/d.diff" <<'DIFF'
diff --git a/app/OldName.php b/app/NewName.php
similarity index 100%
rename from app/OldName.php
rename to app/NewName.php
DIFF
    run bash "${FINDINGS}" --store "${SEC_FINDINGS_STORE}" gate --repo "${REPO}" \
        <"${BATS_TEST_TMPDIR}/d.diff"
    assert_failure 1
    assert_output --partial "unrelated_in_file"
}

@test "an unstaged call site is still seen" {
    # The index lacks the call and the working tree has it: reading only the
    # index would answer PASS for a file that now calls the finding's symbol.
    seed confirmed High app/InvoiceController.php 3
    printf '<?php\nfunction late() {}\n' >"${REPO}/app/Late.php"
    git -C "${REPO}" add app/Late.php
    printf '<?php\nfunction late() { $c->show(1); }\n' >"${REPO}/app/Late.php"

    cat >"${BATS_TEST_TMPDIR}/d.diff" <<'DIFF'
diff --git a/app/Late.php b/app/Late.php
--- /dev/null
+++ b/app/Late.php
@@ -0,0 +1,2 @@
+<?php
+function late() {}
DIFF
    run bash "${FINDINGS}" --store "${SEC_FINDINGS_STORE}" gate --repo "${REPO}" \
        <"${BATS_TEST_TMPDIR}/d.diff"
    assert_failure 1
    assert_output --partial "caller_radius"
}

@test "a new file header does not inherit the previous file's old path" {
    # `--- /dev/null` is not `--- a/...`, so a stale pending_old invented a
    # rename from the first file to the second — and the first file's finding
    # then matched the second file's line numbers as `direct`, a false BLOCK.
    seed confirmed High app/InvoiceController.php 1
    cat >"${BATS_TEST_TMPDIR}/d.diff" <<'DIFF'
diff --git a/app/InvoiceController.php b/app/InvoiceController.php
--- a/app/InvoiceController.php
+++ b/app/InvoiceController.php
@@ -10,0 +11,1 @@
+    // unrelated edit
diff --git a/app/Added.php b/app/Added.php
new file mode 100644
--- /dev/null
+++ b/app/Added.php
@@ -0,0 +1,1 @@
+<?php
DIFF
    run bash "${FINDINGS}" --store "${SEC_FINDINGS_STORE}" gate --repo "${REPO}" \
        <"${BATS_TEST_TMPDIR}/d.diff"
    assert_failure 1
    assert_output --partial "unrelated_in_file"
}

@test "gate fails closed on an empty change set" {
    seed confirmed High app/InvoiceController.php 3
    : >"${BATS_TEST_TMPDIR}/d.diff"
    run bash "${FINDINGS}" --store "${SEC_FINDINGS_STORE}" gate --repo "${REPO}" \
        <"${BATS_TEST_TMPDIR}/d.diff"
    assert_failure 1
    assert_output --partial "empty change set"
}

@test "a stale High finding is a review, never a block" {
    # The verdict predates the file it describes, so it cannot stop a merge.
    seed confirmed High app/InvoiceController.php 3 deadbeef
    diff_on_own_lines >"${BATS_TEST_TMPDIR}/d.diff"
    run bash "${FINDINGS}" --store "${SEC_FINDINGS_STORE}" gate --repo "${REPO}" \
        <"${BATS_TEST_TMPDIR}/d.diff"
    assert_failure 1
    assert_output --partial "stale"
}

# --- snapshot binding -------------------------------------------------------

@test "stale lists a finding whose file moved on" {
    seed confirmed High app/InvoiceController.php 3 deadbeef
    run bash "${FINDINGS}" stale --repo "${REPO}"
    assert_success
    assert_output --partial "stale  SEC-1"
}

@test "stale reports nothing when the finding matches its file" {
    seed confirmed High app/InvoiceController.php 3 "${HEAD_SHA}"
    run bash "${FINDINGS}" stale --repo "${REPO}"
    assert_success
    assert_output --partial "no stale findings"
}

@test "stale ignores a finding that is already closed" {
    seed false_positive High app/InvoiceController.php 3 deadbeef
    run bash "${FINDINGS}" stale --repo "${REPO}"
    assert_success
    assert_output --partial "no stale findings"
}
