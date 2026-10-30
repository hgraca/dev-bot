---
date: 2026-10-24
keywords: ["github-actions", "required-status-check", "skipped-job", "branch-protection", "matrix"]
trigger-on: ["required-status-check-gate", "matrix-job-rename"]
---

## A skipped job reports success, so a required check needs an explicit failure gate

Splitting a job that carries a required branch-protection check name (say `test`) into a build matrix renames the reported checks to `test (1/3)`, `test (2/3)` … and the required `test` check then never reports at all. Adding a gate job with `name: test`, `needs: <matrix-job>` and `if: always()` restores the name, but the gate must **fail explicitly** when a leg failed — `[ "${{ needs.<matrix-job>.result }}" = "success" ]`. Without `if: always()` the gate is skipped whenever a leg fails, and a skipped job reports its status as success: GitHub documents that it will not prevent a pull request from merging, even as a required check. `needs.<matrix-job>.result` is the aggregate result — `success` only when every leg succeeded — so the comparison is the whole guard.
