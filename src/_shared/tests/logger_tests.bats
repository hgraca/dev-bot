#!/usr/bin/env bats
# =============================================================================
# src/_shared/tests/logger_tests.bats
# Tests for the shared logger module at src/_shared/logger.ts.
#
# Run from project root:
#   bats src/_shared/tests/logger_tests.bats
#
# Covers all acceptance criteria:
#   1.  File exists at src/_shared/logger.ts
#   2.  Exports createLogger(opts?) returning object with 6 log methods
#   3.  Exports pre-built singleton logger (no client, no module tag)
#   4.  debug/info/notice write to stderr with timestamp + level prefix + newline
#   5.  warn writes to stderr only (no chat injection)
#   6.  error writes stderr + injects chat when client+sessionId available
#   7.  fatal same as error but with level: "fatal" in metadata
#   8.  error/fatal stderr-only when client or sessionId absent
#   9.  Stderr write failures silently ignored (no throw)
#   10. Chat injection failures silently ignored (no throw)
#   11. createLogger accepts undefined opts
# =============================================================================

setup() {
  bats_require_minimum_version 1.5.0
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
  LOGGER_FILE="$PROJECT_ROOT/src/_shared/logger.ts"

  # Stash bun path for consistent invocation
  BUN="$(command -v bun || true)"
  if [[ -z "$BUN" ]]; then
    BUN="/home/herberto/.bun/bin/bun"
  fi

  # Verify bun availability once
  if [[ ! -x "$BUN" ]]; then
    skip "bun not available"
  fi

  # WORK_DIR under .agents/memory/thinking/ per project convention
  WORK_DIR="$PROJECT_ROOT/.agents/memory/thinking/logger-tests-$(date +%s)-$$"
}

teardown() {
  rm -rf "$WORK_DIR" 2>/dev/null || true
}

# ── Helpers ──────────────────────────────────────────────────────────────────

# Skip a test that requires logger.ts to exist.
_require_logger() {
  if [[ ! -f "$LOGGER_FILE" ]]; then
    skip "logger.ts not yet implemented"
  fi
}

# Run an inline TypeScript snippet via bun and assert success + PASS output.
# Usage: _run_ts '...typescript code...'
_run_ts() {
  local code="$1"
  mkdir -p "$WORK_DIR"
  run "$BUN" -e "$code"
}

# Assert that the last _run_ts invocation printed PASS and exited 0.
_assert_ts_pass() {
  assert_success
  assert_output --partial "PASS"
}

# Assert that the last _run_ts invocation printed a specific FAIL message.
_assert_ts_fail_with() {
  local expected="$1"
  assert_failure
  assert_output --partial "$expected"
}

# ── 1. File existence ───────────────────────────────────────────────────────

@test "1: file exists at src/_shared/logger.ts" {
  test -f "$LOGGER_FILE"
}

# ── 2. Export verification (grep-based) ──────────────────────────────────────

@test "2a: exports createLogger function" {
  _require_logger
  grep -q "export.*createLogger" "$LOGGER_FILE" || fail "createLogger not exported"
}

@test "2b: exports logger singleton" {
  _require_logger
  grep -q "export.*logger" "$LOGGER_FILE" || fail "logger singleton not exported"
}

@test "2c: exports formatMessage function" {
  _require_logger
  grep -q "formatMessage" "$LOGGER_FILE" || fail "formatMessage not found in source"
}

@test "2d: exports writeStderr function" {
  _require_logger
  grep -q "writeStderr" "$LOGGER_FILE" || fail "writeStderr not found in source"
}

@test "2e: exports injectPrompt function" {
  _require_logger
  grep -q "injectPrompt" "$LOGGER_FILE" || fail "injectPrompt not found in source"
}

# ── 3. Compile check ────────────────────────────────────────────────────────

@test "3: compiles without errors via bun build --check" {
  _require_logger
  run "$BUN" build --check "$LOGGER_FILE" 2>&1
  assert_success
}

# ── 4. createLogger returns objects with 6 methods ──────────────────────────

@test "4a: createLogger() returns object with 6 log methods" {
  _require_logger
  _run_ts '
    import { createLogger } from "./src/_shared/logger.ts";
    const log = createLogger();
    const methods = ["debug","info","notice","warn","error","fatal"];
    const missing = methods.filter(m => typeof log[m] !== "function");
    if (missing.length > 0) {
      console.log("FAIL: missing methods", missing.join(","));
      process.exit(1);
    }
    console.log("PASS");
  '
  _assert_ts_pass
}

@test "4b: createLogger({ module, client, sessionId }) accepts all opts" {
  _require_logger
  _run_ts '
    import { createLogger } from "./src/_shared/logger.ts";
    const log = createLogger({
      module: "test-mod",
      client: { session: { prompt: () => {} } },
      sessionId: "sess-1"
    });
    console.log("PASS");
  '
  _assert_ts_pass
}

# ── 5. Pre-built singleton ──────────────────────────────────────────────────

@test "5a: logger is a pre-built singleton with 6 methods" {
  _require_logger
  _run_ts '
    import { logger } from "./src/_shared/logger.ts";
    const methods = ["debug","info","notice","warn","error","fatal"];
    const missing = methods.filter(m => typeof logger[m] !== "function");
    if (missing.length > 0) {
      console.log("FAIL: missing methods on logger", missing.join(","));
      process.exit(1);
    }
    console.log("PASS");
  '
  _assert_ts_pass
}

@test "5b: singleton logger writes to stderr without module tag" {
  _require_logger
  _run_ts '
    import { logger } from "./src/_shared/logger.ts";
    const captured: string[] = [];
    const orig = process.stderr.write.bind(process.stderr);
    process.stderr.write = (chunk: any) => { captured.push(chunk.toString()); return true; };
    logger.info("singleton test");
    process.stderr.write = orig;
    const out = captured.join("");
    // Must write to stderr
    if (out.length === 0) { console.log("FAIL: no stderr output"); process.exit(1); }
    // Must have level prefix
    if (!out.includes("[INFO]")) { console.log("FAIL: missing [INFO] level"); process.exit(1); }
    // Must have the message
    if (!out.includes("singleton test")) { console.log("FAIL: missing message"); process.exit(1); }
    // Should not have a module tag (since singleton has no module)
    if (out.includes("[test-mod]")) { console.log("FAIL: unexpected module tag"); process.exit(1); }
    console.log("PASS");
  '
  _assert_ts_pass
}

# ── 6. Output format (debug/info/notice) ────────────────────────────────────

@test "6a: info writes to stderr with timestamp, [INFO], module tag, message, newline" {
  _require_logger
  _run_ts '
    import { createLogger } from "./src/_shared/logger.ts";
    const captured: string[] = [];
    const orig = process.stderr.write.bind(process.stderr);
    process.stderr.write = (chunk: any) => { captured.push(chunk.toString()); return true; };
    const log = createLogger({ module: "mymod" });
    log.info("hello world");
    process.stderr.write = orig;
    const out = captured.join("");

    // Check ISO timestamp: [2026-06-13T...
    if (!/^\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/.test(out)) {
      console.log("FAIL: missing ISO timestamp in: " + out.replace(/\n/g, "\\n"));
      process.exit(1);
    }
    // Check level prefix
    if (!out.includes("[INFO]")) {
      console.log("FAIL: missing [INFO] in: " + out.replace(/\n/g, "\\n"));
      process.exit(1);
    }
    // Check module tag
    if (!out.includes("[mymod]")) {
      console.log("FAIL: missing [mymod] tag in: " + out.replace(/\n/g, "\\n"));
      process.exit(1);
    }
    // Check message
    if (!out.includes("hello world")) {
      console.log("FAIL: missing message in: " + out.replace(/\n/g, "\\n"));
      process.exit(1);
    }
    // Check newline termination
    if (!out.endsWith("\n")) {
      console.log("FAIL: missing trailing newline");
      process.exit(1);
    }
    console.log("PASS");
  '
  _assert_ts_pass
}

@test "6b: debug writes to stderr with [DEBUG] prefix" {
  _require_logger
  _run_ts '
    import { createLogger } from "./src/_shared/logger.ts";
    const captured: string[] = [];
    const orig = process.stderr.write.bind(process.stderr);
    process.stderr.write = (chunk: any) => { captured.push(chunk.toString()); return true; };
    const log = createLogger({ module: "dbg" });
    log.debug("debug msg");
    process.stderr.write = orig;
    const out = captured.join("");
    if (!out.includes("[DEBUG]")) { console.log("FAIL: missing [DEBUG]"); process.exit(1); }
    if (!out.includes("debug msg")) { console.log("FAIL: missing message"); process.exit(1); }
    console.log("PASS");
  '
  _assert_ts_pass
}

@test "6c: notice writes to stderr with [NOTICE] prefix" {
  _require_logger
  _run_ts '
    import { createLogger } from "./src/_shared/logger.ts";
    const captured: string[] = [];
    const orig = process.stderr.write.bind(process.stderr);
    process.stderr.write = (chunk: any) => { captured.push(chunk.toString()); return true; };
    const log = createLogger({ module: "ntc" });
    log.notice("notice msg");
    process.stderr.write = orig;
    const out = captured.join("");
    if (!out.includes("[NOTICE]")) { console.log("FAIL: missing [NOTICE]"); process.exit(1); }
    if (!out.includes("notice msg")) { console.log("FAIL: missing message"); process.exit(1); }
    console.log("PASS");
  '
  _assert_ts_pass
}

# ── 7. warn: stderr only, no injection ──────────────────────────────────────

@test "7: warn writes to stderr only, does not inject chat prompt" {
  _require_logger
  _run_ts '
    import { createLogger } from "./src/_shared/logger.ts";
    const captured: string[] = [];
    const orig = process.stderr.write.bind(process.stderr);
    process.stderr.write = (chunk: any) => { captured.push(chunk.toString()); return true; };
    let promptCalled = false;
    const client = {
      session: { prompt: () => { promptCalled = true; } }
    };
    const log = createLogger({ client, sessionId: "s1", module: "warn-test" });
    log.warn("warning message");
    process.stderr.write = orig;
    if (captured.length === 0) { console.log("FAIL: no stderr output"); process.exit(1); }
    if (!captured.join("").includes("[WARN]")) { console.log("FAIL: missing [WARN] prefix"); process.exit(1); }
    if (promptCalled) { console.log("FAIL: warn should not inject chat prompt"); process.exit(1); }
    console.log("PASS");
  '
  _assert_ts_pass
}

# ── 8. error: stderr + inject ────────────────────────────────────────────────

@test "8a: error writes to stderr and injects chat prompt with level 'error'" {
  _require_logger
  _run_ts '
    import { createLogger } from "./src/_shared/logger.ts";
    const captured: string[] = [];
    const orig = process.stderr.write.bind(process.stderr);
    process.stderr.write = (chunk: any) => { captured.push(chunk.toString()); return true; };
    let promptCalled = false;
    let promptMsg = "";
    let promptLevel = "";
    const client = {
      session: {
        prompt: (arg: any) => {
          promptCalled = true;
          promptMsg = arg?.body?.parts?.[0]?.text;
          promptLevel = arg?.body?.parts?.[0]?.metadata?.level;
        }
      }
    };
    const log = createLogger({ client, sessionId: "s1", module: "err-test" });
    log.error("error message");
    process.stderr.write = orig;
    if (captured.length === 0) { console.log("FAIL: no stderr output"); process.exit(1); }
    if (!captured.join("").includes("[ERROR]")) { console.log("FAIL: missing [ERROR] prefix"); process.exit(1); }
    if (!promptCalled) { console.log("FAIL: error should inject chat prompt"); process.exit(1); }
    if (promptLevel !== "error") { console.log("FAIL: expected level 'error', got " + promptLevel); process.exit(1); }
    if (promptMsg !== "error message") { console.log("FAIL: expected msg [error message], got [" + promptMsg + "]"); process.exit(1); }
    console.log("PASS");
  '
  _assert_ts_pass
}

# ── 9. fatal: stderr + inject with level "fatal" ─────────────────────────────

@test "9: fatal writes to stderr and injects chat prompt with level 'fatal'" {
  _require_logger
  _run_ts '
    import { createLogger } from "./src/_shared/logger.ts";
    const captured: string[] = [];
    const orig = process.stderr.write.bind(process.stderr);
    process.stderr.write = (chunk: any) => { captured.push(chunk.toString()); return true; };
    let promptCalled = false;
    let promptLevel = "";
    const client = {
      session: {
        prompt: (arg: any) => {
          promptCalled = true;
          promptLevel = arg?.body?.parts?.[0]?.metadata?.level;
        }
      }
    };
    const log = createLogger({ client, sessionId: "s1", module: "fat-test" });
    log.fatal("fatal message");
    process.stderr.write = orig;
    if (captured.length === 0) { console.log("FAIL: no stderr output"); process.exit(1); }
    if (!captured.join("").includes("[FATAL]")) { console.log("FAIL: missing [FATAL] prefix"); process.exit(1); }
    if (!promptCalled) { console.log("FAIL: fatal should inject chat prompt"); process.exit(1); }
    if (promptLevel !== "fatal") { console.log("FAIL: expected level 'fatal', got " + promptLevel); process.exit(1); }
    console.log("PASS");
  '
  _assert_ts_pass
}

# ── 10. error/fatal stderr-only when client absent ───────────────────────────

@test "10a: error is stderr-only when client is absent (no injection)" {
  _require_logger
  _run_ts '
    import { createLogger } from "./src/_shared/logger.ts";
    const captured: string[] = [];
    const orig = process.stderr.write.bind(process.stderr);
    process.stderr.write = (chunk: any) => { captured.push(chunk.toString()); return true; };
    // No client provided
    const log = createLogger({ sessionId: "s1", module: "test" });
    log.error("error without client");
    process.stderr.write = orig;
    if (captured.length === 0) { console.log("FAIL: no stderr output"); process.exit(1); }
    if (!captured.join("").includes("[ERROR]")) { console.log("FAIL: missing [ERROR]"); process.exit(1); }
    // If we got here without throwing, injection was skipped successfully
    console.log("PASS");
  '
  _assert_ts_pass
}

@test "10b: fatal is stderr-only when sessionId is absent (no injection)" {
  _require_logger
  _run_ts '
    import { createLogger } from "./src/_shared/logger.ts";
    const captured: string[] = [];
    const orig = process.stderr.write.bind(process.stderr);
    process.stderr.write = (chunk: any) => { captured.push(chunk.toString()); return true; };
    let promptCalled = false;
    const client = {
      session: { prompt: () => { promptCalled = true; } }
    };
    // No sessionId provided
    const log = createLogger({ client, module: "test" });
    log.fatal("fatal without sessionId");
    process.stderr.write = orig;
    if (captured.length === 0) { console.log("FAIL: no stderr output"); process.exit(1); }
    if (promptCalled) { console.log("FAIL: should not inject without sessionId"); process.exit(1); }
    console.log("PASS");
  '
  _assert_ts_pass
}

@test "10c: error is stderr-only when both client and sessionId are absent" {
  _require_logger
  _run_ts '
    import { createLogger } from "./src/_shared/logger.ts";
    const captured: string[] = [];
    const orig = process.stderr.write.bind(process.stderr);
    process.stderr.write = (chunk: any) => { captured.push(chunk.toString()); return true; };
    const log = createLogger({ module: "test" });  // no client, no sessionId
    log.error("bare error");
    log.fatal("bare fatal");
    process.stderr.write = orig;
    if (captured.length === 0) { console.log("FAIL: no stderr output"); process.exit(1); }
    if (!captured.join("").includes("[ERROR]")) { console.log("FAIL: missing [ERROR]"); process.exit(1); }
    if (!captured.join("").includes("[FATAL]")) { console.log("FAIL: missing [FATAL]"); process.exit(1); }
    console.log("PASS");
  '
  _assert_ts_pass
}

# ── 11. Stderr write failures silently ignored ──────────────────────────────

@test "11a: stderr.write throwing does not propagate to caller (debug/info)" {
  _require_logger
  _run_ts '
    import { createLogger } from "./src/_shared/logger.ts";
    const orig = process.stderr.write.bind(process.stderr);
    let callCount = 0;
    process.stderr.write = () => { callCount++; throw new Error("stderr fail"); };
    const log = createLogger({ module: "test" });
    // None of these should throw
    try {
      log.debug("d");
      log.info("i");
      log.notice("n");
      console.log("PASS: all " + callCount + " stderr writes silently swallowed");
    } catch (e: any) {
      console.log("FAIL: exception escaped: " + e.message);
      process.exit(1);
    } finally {
      process.stderr.write = orig;
    }
  '
  _assert_ts_pass
}

@test "11b: stderr.write throwing does not propagate to caller (warn/error/fatal)" {
  _require_logger
  _run_ts '
    import { createLogger } from "./src/_shared/logger.ts";
    const orig = process.stderr.write.bind(process.stderr);
    let callCount = 0;
    process.stderr.write = () => { callCount++; throw new Error("stderr fail"); };
    const client = { session: { prompt: () => {} } };
    const log = createLogger({ module: "test", client, sessionId: "s1" });
    try {
      log.warn("w");
      log.error("e");
      log.fatal("f");
      console.log("PASS: all " + callCount + " stderr writes silently swallowed");
    } catch (e: any) {
      console.log("FAIL: exception escaped: " + e.message);
      process.exit(1);
    } finally {
      process.stderr.write = orig;
    }
  '
  _assert_ts_pass
}

# ── 12. Chat injection failures silently ignored ────────────────────────────

@test "12: chat injection throw does not propagate to caller" {
  _require_logger
  _run_ts '
    import { createLogger } from "./src/_shared/logger.ts";
    const client = {
      session: {
        prompt: () => { throw new Error("inject fail"); }
      }
    };
    const log = createLogger({ client, sessionId: "s1", module: "test" });
    try {
      log.error("error with failing inject");
      log.fatal("fatal with failing inject");
      console.log("PASS");
    } catch (e: any) {
      console.log("FAIL: inject exception escaped: " + e.message);
      process.exit(1);
    }
  '
  _assert_ts_pass
}

# ── 13. createLogger with undefined opts ─────────────────────────────────────

@test "13: createLogger(undefined) returns valid logger" {
  _require_logger
  _run_ts '
    import { createLogger } from "./src/_shared/logger.ts";
    const log = createLogger(undefined);
    const methods = ["debug","info","notice","warn","error","fatal"];
    for (const m of methods) {
      if (typeof log[m] !== "function") {
        console.log("FAIL: missing method " + m + " with undefined opts");
        process.exit(1);
      }
    }
    // Calling methods should not throw
    try {
      log.info("test with undefined opts");
      log.error("error with undefined opts");
      log.fatal("fatal with undefined opts");
      console.log("PASS");
    } catch (e: any) {
      console.log("FAIL: exception with undefined opts: " + e.message);
      process.exit(1);
    }
  '
  _assert_ts_pass
}

# ── 14. formatMessage output format (tested through level calls) ─────────────

@test "14: all level prefixes appear correctly in stderr output" {
  _require_logger
  _run_ts '
    import { createLogger } from "./src/_shared/logger.ts";
    const captured: string[] = [];
    const orig = process.stderr.write.bind(process.stderr);
    process.stderr.write = (chunk: any) => { captured.push(chunk.toString()); return true; };
    const log = createLogger({ module: "levels" });
    log.debug("d"); log.info("i"); log.notice("n");
    log.warn("w"); log.error("e"); log.fatal("f");
    process.stderr.write = orig;
    const out = captured.join("");
    const expected = ["[DEBUG]","[INFO]","[NOTICE]","[WARN]","[ERROR]","[FATAL]"];
    for (const prefix of expected) {
      if (!out.includes(prefix)) {
        console.log("FAIL: missing " + prefix);
        process.exit(1);
      }
    }
    console.log("PASS");
  '
  _assert_ts_pass
}

@test "15: log messages ending in stderr are separated by newlines" {
  _require_logger
  _run_ts '
    import { createLogger } from "./src/_shared/logger.ts";
    const captured: string[] = [];
    const orig = process.stderr.write.bind(process.stderr);
    process.stderr.write = (chunk: any) => { captured.push(chunk.toString()); return true; };
    const log = createLogger({ module: "nl" });
    log.info("msg1");
    log.info("msg2");
    process.stderr.write = orig;
    const out = captured.join("");
    // Each call to writeStderr should produce exactly one newline-terminated string
    const lines = out.split("\n").filter(l => l.length > 0);
    if (lines.length < 2) {
      console.log("FAIL: expected at least 2 non-empty lines, got " + lines.length);
      process.exit(1);
    }
    console.log("PASS");
  '
  _assert_ts_pass
}

# ── Edge case: empty module tag ─────────────────────────────────────────────

@test "16: createLogger with empty module string works without error" {
  _require_logger
  _run_ts '
    import { createLogger } from "./src/_shared/logger.ts";
    const log = createLogger({ module: "" });
    log.info("empty module test");
    console.log("PASS");
  '
  _assert_ts_pass
}

# ── 17. logFile option (audit-24 NOTE-2): writes to file by default ─────────

@test "17a: createLogger({ logFile }) appends log lines to the file" {
  _require_logger
  mkdir -p "$WORK_DIR"
  local logf="$WORK_DIR/hooks.log"
  _run_ts '
    import { createLogger } from "./src/_shared/logger.ts";
    const log = createLogger({ module: "hooks", logFile: "'$logf'" });
    log.info("first line");
    log.warn("second line");
    // small delay for file flush (sync write — should already be on disk)
    const fs = require("fs");
    const content = fs.readFileSync("'$logf'", "utf8");
    if (!content.includes("[INFO]") || !content.includes("first line")) {
      console.log("FAIL: info line missing from file");
      process.exit(1);
    }
    if (!content.includes("[WARN]") || !content.includes("second line")) {
      console.log("FAIL: warn line missing from file");
      process.exit(1);
    }
    console.log("PASS");
  '
  _assert_ts_pass
}

@test "17b: logFile creates parent directories" {
  _require_logger
  local logf="$WORK_DIR/nested/deep/hooks.log"
  _run_ts '
    import { createLogger } from "./src/_shared/logger.ts";
    const log = createLogger({ module: "hooks", logFile: "'$logf'" });
    log.error("deep path test");
    const fs = require("fs");
    if (!fs.existsSync("'$logf'")) {
      console.log("FAIL: file not created in nested dir");
      process.exit(1);
    }
    console.log("PASS");
  '
  _assert_ts_pass
}

@test "17c: logFile failure is silently ignored (no throw)" {
  _require_logger
  _run_ts '
    import { createLogger } from "./src/_shared/logger.ts";
    // A path that cannot be written (parent is a file)
    const log = createLogger({ module: "hooks", logFile: "/proc/1/nonexistent/x.log" });
    try {
      log.info("should not throw");
      console.log("PASS");
    } catch (e: any) {
      console.log("FAIL: logFile failure escaped: " + e.message);
      process.exit(1);
    }
  '
  _assert_ts_pass
}

@test "17d: without logFile, no file is written (backwards compatible)" {
  _require_logger
  mkdir -p "$WORK_DIR"
  local logf="$WORK_DIR/never-written.log"
  _run_ts '
    import { createLogger } from "./src/_shared/logger.ts";
    const log = createLogger({ module: "hooks" });
    log.info("no logFile set");
    const fs = require("fs");
    if (fs.existsSync("'$logf'")) {
      console.log("FAIL: file written without logFile option");
      process.exit(1);
    }
    console.log("PASS");
  '
  _assert_ts_pass
}

# ── 18. logFile replaces stderr (no duplicate screen output) ─────────────────
# audit-25: starting opencode printed 2 lines before the TUI — the plugin-load
# logger.info calls went to stderr even though a logFile was configured. With a
# logFile set, the file is the log destination; stderr must stay quiet.

@test "18a: with logFile, info does NOT write to stderr" {
  _require_logger
  mkdir -p "$WORK_DIR"
  local logf="$WORK_DIR/hooks.log"
  _run_ts '
    import { createLogger } from "./src/_shared/logger.ts";
    const captured: string[] = [];
    const orig = process.stderr.write.bind(process.stderr);
    process.stderr.write = (chunk: any) => { captured.push(chunk.toString()); return true; };
    const log = createLogger({ module: "hooks", logFile: "'$logf'" });
    log.info("loaded plugin hook test from somewhere");
    process.stderr.write = orig;
    const fs = require("fs");
    const content = fs.readFileSync("'$logf'", "utf8");
    if (!content.includes("loaded plugin hook test")) {
      console.log("FAIL: info not in log file");
      process.exit(1);
    }
    if (captured.length > 0) {
      console.log("FAIL: info leaked to stderr despite logFile: " + captured.join(""));
      process.exit(1);
    }
    console.log("PASS");
  '
  _assert_ts_pass
}

@test "18b: with logFile, warn/error/fatal do NOT write to stderr either" {
  _require_logger
  mkdir -p "$WORK_DIR"
  local logf="$WORK_DIR/hooks.log"
  _run_ts '
    import { createLogger } from "./src/_shared/logger.ts";
    const captured: string[] = [];
    const orig = process.stderr.write.bind(process.stderr);
    process.stderr.write = (chunk: any) => { captured.push(chunk.toString()); return true; };
    const log = createLogger({ module: "hooks", logFile: "'$logf'" });
    log.warn("watchdog check failed");
    log.error("abort failed");
    log.fatal("boom");
    process.stderr.write = orig;
    const fs = require("fs");
    const content = fs.readFileSync("'$logf'", "utf8");
    if (!content.includes("[WARN]") || !content.includes("[ERROR]") || !content.includes("[FATAL]")) {
      console.log("FAIL: levels missing from log file");
      process.exit(1);
    }
    if (captured.length > 0) {
      console.log("FAIL: warn/error/fatal leaked to stderr despite logFile: " + captured.join(""));
      process.exit(1);
    }
    console.log("PASS");
  '
  _assert_ts_pass
}

@test "18c: without logFile, stderr still receives all levels (backwards compatible)" {
  _require_logger
  _run_ts '
    import { createLogger } from "./src/_shared/logger.ts";
    const captured: string[] = [];
    const orig = process.stderr.write.bind(process.stderr);
    process.stderr.write = (chunk: any) => { captured.push(chunk.toString()); return true; };
    const log = createLogger({ module: "plain" });
    log.info("no logfile info");
    log.warn("no logfile warn");
    process.stderr.write = orig;
    if (!captured.join("").includes("[INFO]")) { console.log("FAIL: info missing from stderr"); process.exit(1); }
    if (!captured.join("").includes("[WARN]")) { console.log("FAIL: warn missing from stderr"); process.exit(1); }
    console.log("PASS");
  '
  _assert_ts_pass
}
