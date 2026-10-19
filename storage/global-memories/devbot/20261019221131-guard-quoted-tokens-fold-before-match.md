---
date: 2026-10-19
keywords: ["devbot", "guards", "shell", "quoting", "command-matching"]
aliases: ["quoted token folding", "guard bypass with quotes", "git \"push\" --force"]
trigger-on: ["devbot-guard-rule"]
---

## Command guards fold quoted tokens before matching

`guards.ts` evaluates each rule against both the raw command segment and a
quote-folded form: every quoted token is unwrapped, and the whitespace inside it
becomes `\x1f` (a non-whitespace byte patterns match as token text). Folding is
what makes `git "push" --force`, `git "-C" /path push --force` and `git
"push" --force-with-lease` hit a literal `git push --force` rule. Testing only
the folded form is wrong: internal whitespace is preserved as `\x1f`, so a fully
quoted argument such as `echo 'git push --force'` stays one opaque token and
does not match an anchored rule (`echo` is not a command runner), while the raw
form keeps `bash -c "git push --force"` visible to the unanchored runner path.
A new guard rule needs both cases in its BATS test — the folded form proves the
bypass is closed, the raw form proves prose is not blocked.
