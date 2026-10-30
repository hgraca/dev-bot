---
date: 2026-10-23
keywords: ["devbot", "guards", "force-push", "sudo", "heredoc"]
aliases: ["guard blocked my command", "force push is prohibited", "sudo requires approval"]
---

## Project guards match the command text, including heredoc bodies

A project's `guards` in `.devbot.project.jsonc` are regexes applied to the command string, so they also match text inside a heredoc or a Python script passed to `bash -c` — writing "sudo chown …" or "git push --force" as *data* blocks the whole command. GET-E/dev-tools blocks `rm -rf`, `sudo .*` and `git push --force` (the last also matches `--force-with-lease`, so squashing a pushed PR branch needs the human to run the push, or an explicit decision to lift the guard).

Write the file with the `write`/`edit` tools instead of a shell heredoc when its content must contain those strings, then run a plain command on it. Do not route around a guard by another command that achieves the same effect — surface it and ask.
