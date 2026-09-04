---
date: 2026-09-04
keywords: ["devbot", "e2e", "docker", "stdin", "exec"]
---

# dev-bot e2e: `docker run -it` stdin can silently stop reaching the shell — use detached run + `docker exec -it`

The `test-cc.sh`/`test-oc.sh` rigs (tests/test-project) originally ended with an
interactive `bash -i` inside a `docker run -it` container. Across several
terminals (JetBrains, GNOME) typing showed nothing — no echo, no prompt — while
Ctrl+C "worked" and `docker exec -it <name> bash` from the same terminal gave a
perfect prompt. Live forensics proved the container side was healthy (the pty
accepted input when fed via `docker attach` from a pty; the `docker run -it`
flags were byte-identical to the era when it worked). Conclusion: the
`docker run -it` client-side stdin link is the fragile part, not the script.

Fix (committed in the rig): run the container **detached** (`docker run -d`),
stream phase output with `docker logs -f`, have the inner script touch
`.agents/.test-ready` on the host mount when its phases finish, then attach the
interactive shell with `docker exec -it <name> bash` — the path proven to echo
input. Related gotchas:

- `docker attach` refuses stdin unless the caller has a real tty ("stdin is not
  a terminal") — piping input into attach from a non-tty fails.
- Writing to `/dev/pts/<N>` (the pty **slave**) sends text to the SCREEN, not
  keystrokes to the shell; keystrokes must be written to the pty **master**,
  which only the docker client holds.
- A pty showing `ECHO=off ICANON=off ISIG=on` is readline's normal raw state at
  a prompt — not proof of breakage; readline echoes keystrokes itself.
- `docker exec` shells are non-login: they only read `~/.bashrc`, so PATH for
  `devbot`/`opencode` must be exported there (the rig now does).
- "Hang before the prompt" was often really a silent multi-minute phase (qmd/
  npm lock waits); lock waits now print a one-time notice.
