---
name: devbot:audit-testsuite
description: "Produces test reports documenting test results, bugs found, and coverage assessment. Use this skill whenever you finish writing or running a test suite and need to document the results — even if you do not say 'audit' explicitly."
---

# Skill: Test Reporting

Document test results, bugs found, production code changes, and coverage assessment in structured report.

## When to Apply

- After completing test writing session (pre-implementation)
- After completing test validation (post-implementation)
- After test audit

## Test Report

Save to `<issue-folder>/TEST-REPORT-YYYY-MM-DD-NNN.md`.

### Template

> # Test Report
>
> **Test Suite Result**: PASS | FAIL (total tests, passed, failed, skipped)
>
> ## Tests Created
>
> ### Integration Tests
>
> - `<test_identifier>` — What this test verifies.
>
> ### Unit Tests
>
> - `<test_identifier>` — What this test verifies.
>
> ## Tests Removed
>
> _If none: "No tests removed."_
>
> - `<test_identifier>` — Why removed (redundant, nonsensical, low-value, etc.).
>
> ## Bugs Found
>
> _If none: "No bugs found."_
>
> ### Bug <n>: <Title>
>
> - **Severity**: CRITICAL | MAJOR | MINOR
> - **Steps to reproduce**: Numbered steps.
> - **Expected**: What should happen.
> - **Actual**: What actually happens.
> - **Affected test**: Test that exposed this bug (if any).
>
> ## Production Code Changes
>
> _If none: "No production code was modified."_
>
> - **File path**: File modified.
> - **What changed**: Exact description.
> - **Why**: Why production code untestable without this change.
>
> ## Coverage Assessment
>
> Brief assessment of acceptance criteria coverage. List criteria lacking test coverage and explain why.
>
> ## Tools used
>
> ### SKILLS
>
> List skills used by agent while creating report, or "None."
>
> ### MCP tools
>
> List MCP tools used by agent while creating report, or "None."

### Bug Severity Definitions

- **CRITICAL** — Breaks core functionality or causes data loss.
- **MAJOR** — Significant incorrect behavior with workaround.
- **MINOR** — Cosmetic or low-impact issue.
