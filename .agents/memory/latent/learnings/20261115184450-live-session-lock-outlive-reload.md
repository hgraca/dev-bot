---
date: 2026-11-15
keywords: ["devbot", "datasources", "bats", "flake", "flock"]
aliases: ["live session fixture 5s lock", "reload flake full suite", "sleep too short fixture"]
---

# A live-session fixture must hold its lock longer than the slowest run, not the typical one

`_live_session` in `src/agentic/datasources/tests/datasources_tests.bats` writes a session file and holds a `flock` on it for a fixed `sleep`, so the reload under test sees a live project. At `sleep 5` it passed in isolation (the test takes ~5 s) and failed **every** time inside a full `make test`, where the same render took 12–15 s: by the time reload listed live sessions the lock was gone, so the expected warning never printed. The lesson generalises to any test fixture that simulates liveness with a timer — size the window against the slowest observed run (here 60 s; the detached subshell exits on its own), and treat a test that is green alone and red in the suite as a timing bug, not ordering.
