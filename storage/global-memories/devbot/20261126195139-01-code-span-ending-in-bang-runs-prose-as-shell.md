---
date: 2026-11-26
keywords: ["devbot", "inline-shell", "slash-command", "claude-code", "markdown"]
aliases: ["bang before backtick", "fixup corrupts the command", "dynamic context injection"]
trigger-on: ["devbot-command-markdown", "claude-code-skill-markdown"]
---

## A code span ending in a bang closes on the harness's inline-shell directive

A command or skill body is rendered before it runs: Claude Code turns an exclamation mark immediately followed by a backtick into a shell command and splices its output in place, and OpenCode does the same for commands. A markdown code span whose content ends in a bang therefore closes on that pair — fixup! is the usual one — so the renderer executes the prose after it and splices the result into the body. Symptom seen in `devbot:full-review-loop`: the "Must not" bullet showed `/bin/bash: line 1: commits:: command not found` plus two more error lines where the rule should have been, because the span ended at "fixup" and the command ran from "commits:" to the next backtick in the file. There is no formatting repair — a span cannot carry a trailing bang — so write the marker unquoted and keep `src/harnesses/claudecode/tests/inline_shell_tests.bats` green: it scans every `commands/*.md` and `skills/*/SKILL.md`, plants an offender of each kind, and fails when the scan reaches nothing.
