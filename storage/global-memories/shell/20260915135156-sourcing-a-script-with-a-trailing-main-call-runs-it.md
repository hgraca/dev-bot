---
date: 2026-09-15
keywords: ["shell", "bash", "source", "main", "sourcing"]
trigger-on: ["sourcing-a-script", "shell-script-with-main"]
---

## Sourcing a script that ends in `main "$@"` executes it

A shell script structured with a trailing top-level `main "$@"` runs its whole body the moment it is **sourced**, not just when executed. `source bin/up.sh` inside a test or a helper does not merely define its functions — it triggers the full command.

Observed impact: a test written to call one helper did `bash -c "source '.../bin/up.sh'; _helper ..."` and thereby ran the real start procedure (compose up, config rebuild, module scripts) as a side effect. It happened to be a no-op because the services were already running, but the test's assertions failed on the unexpected output and the blast radius was pure luck.

Three ways to make a script safely sourceable or safely sourced:

- Extract the logic into the shared library and source that; call the library function directly.
- Guard the entry point: `[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"`.
- In the test, strip the call first — the pattern already used elsewhere: `sed '/^main "\$@"/d' src > sandbox/script.sh` — then source the stripped copy.

Diagnostic habit: if sourcing a script produces output, hangs, or touches the system, the script has a top-level entry point. Check the last line before sourcing anything.
