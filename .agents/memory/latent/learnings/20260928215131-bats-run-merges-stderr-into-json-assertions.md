---
date: 2026-09-28
keywords: ["forensics", "bats", "testing", "stderr", "json"]
---

# BATS `run` merges stderr into `$output` — a stderr `WARN` breaks a JSON assertion

BATS `run` captures stdout **and** stderr into `$output`. So a command that prints machine-readable JSON to stdout and a `WARN:` to stderr becomes, under `run`, a single mixed stream — and `echo "${output}" | python3 -c 'json.load(...)'` then fails on the `WARN` line. The production design is still correct (keep stdout clean for JSON consumers, send `WARN:`/`ERROR:` to stderr); the trap is only in the test. Fixes: assert against a fixture that emits no warning, use `run --separate-stderr` (BATS ≥ 1.5) and parse `${stderr}`/`${output}` separately, or write the JSON to a file in the command under test and read that. Hit while testing `forensics prs --format json` against a fixture source adapter that returned a partial `errors` list (surfaced as a `WARN` on stderr): the assertion parsed a JSON body prefixed by `WARN: …` and failed.
