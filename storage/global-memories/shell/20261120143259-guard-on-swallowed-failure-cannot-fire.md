---
date: 2026-11-20
keywords: ["shell", "bash", "testing", "error-handling"]
aliases: ["guard that can never fire", "swallowed exit status", "resolver returns a fallback on failure"]
trigger-on: ["guard-against-silent-empty"]
---

## A guard on a helper that swallows its own failure can never fire

A caller cannot detect a helper's failure by checking its exit status when the helper converts that
failure into a fallback value and exits 0 — `python3 … 2>/dev/null || echo "[]"` does exactly this, and
the same pattern (`|| true`, `|| echo default`, `catch { return default }`) is common wherever a resolver
must always return something. A guard written against the status is decorative: it reads as protection,
never triggers, and the real failure surfaces later as a wrong answer attributed to something else
("this link is missing" when the truth is "the resolver had no inputs"). Two fixes, in order of
preference: make the helper distinguish failure from an empty result (a sentinel that cannot collide
with a legitimate value, or a separate `--strict` mode), or guard the **dependency** the helper needs —
the interpreter, the config file — which is the thing that is actually observable from outside. Either
way, prove the guard by breaking the input and watching it fire; an unproven guard is worse than none,
because it ends the search for the real one.
