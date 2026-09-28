---
date: 2026-09-27
keywords: ["shell", "argmax", "argv", "stdin", "docker"]
trigger-on: ["passing-file-list-to-subprocess", "large-argv", "docker-run-materialised-paths"]
---

## A per-file argv list hits ARG_MAX on large repositories — stream it on stdin

Passing one path per argument (`java Metrics.java "${files[@]}"`, `docker run … cmd "${container[@]}"`) works in tests and dies at scale: a repo with ~10k+ files produces argv approaching the ~2 MB `ARG_MAX`, and `docker run` materialises every element again for the in-container process. Have the driver read the list from stdin (one path per line) and feed it with `printf '%s\n' "${files[@]}" | cmd` — add `-i` to `docker run` so stdin reaches the container. This also keeps the driver's file list separate from any JSON request payload on a plugin's own stdin.
