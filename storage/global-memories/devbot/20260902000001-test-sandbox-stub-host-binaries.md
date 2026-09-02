---
date: 2026-09-02
keywords: ["devbot", "test", "bats", "php", "sandbox", "PATH"]
trigger-on: ["test-path-isolation", "sandbox-host-binary"]
---

## Bats tests that isolate via PATH must stub every probed host binary — a host install silently breaks them

A test that simulates "tool X unavailable" by pointing PATH at a sandbox dir
(`PATH="${bin_dir}:$(dirname "$(command -v python3)")"`) only works if no real
X is reachable through the _rest_ of PATH. `dirname python3` usually resolves
to /usr/bin — which on many hosts also holds php, node, etc. The moment a user
installs php-cli on the host, the tool under test finds real php via
/usr/bin, takes the success path, and the "degraded" assertion fails. Fix: put
a failing stub for every binary the tool probes INTO the sandbox bin dir (e.g.
a `php` stub exiting 127) so it precedes /usr/bin in PATH and shadows the host
binary deterministically. Never `skip` the test when the host binary exists —
that silently converts a real assertion into a no-op. The stub must live only
in the sandbox; the host binary is never invoked or modified. Symptom of the
original bug: tool output looked like a clean success with no degraded marker.
