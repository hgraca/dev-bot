---
date: 2026-10-07
keywords: ["docker", "compose", "bind-mount", "root-owned", "directory"]
aliases: ["mount source path created as directory", "not a directory mount error"]
trigger-on: ["docker-compose-bind-mount", "docker-compose-missing-mount-source"]
---

## A missing bind-mount source is created as a root-owned directory

When a compose service bind-mounts a host path that does not exist (typically a gitignored file
such as `.docker/xdebug.overrides.ini`), `docker compose up` does not fail cleanly: the container
is *created* but starting it fails with `not a directory: Are you trying to mount a directory
onto a file (or vice-versa)?`, and Docker has meanwhile created a **directory** at the host path —
owned by root, because the daemon created it. The intended file can then never be mounted, and a
later `cp file.dist file` fails with `Permission denied` (it tries to write `file/file.dist`
inside that directory). Recover with `rmdir` on the empty created directory — removing an entry
needs write permission on the *parent*, so no `sudo` is required — and create the file before the
next `up`. Do not reach for `rm -rf` on the root-owned directory.
