---
date: 2026-09-24
keywords: ["docker", "bind-mount", "stdin", "ownership"]
trigger-on: ["docker-run-piped-stdin", "docker-nested-bind-mount", "container-file-ownership"]
---

## Driving a tool in a container: piped stdin, nested mounts, and file ownership

Three things bite when a host script pipes a request into a containerised tool.
**Piped stdin needs `-i`.** `printf … | docker run --rm image cmd` runs with stdin
detached: the program reads EOF and reports empty input, with no error from
Docker — the symptom looks like a bug in the tool. Always pass `-i` for piped
input (this is a different failure from the interactive-TTY stdin problem, where
`docker run -it` stops delivering keystrokes to a shell). **A bind mount cannot
be nested inside a read-only bind mount.** Mounting a tool's script at `/x` with
`:ro` and then trying to mount its dependencies at `/x/node_modules` fails with
`mkdirat … read-only file system`, because Docker must create the nested
mountpoint in the already-mounted parent. Mount the writable parent and put the
script inside it, or mount the dependency tree at an unrelated path.
**Container writes take the identity of what they touch.** Running as root,
overwriting an *existing* file preserves its host owner (the inode is truncated,
not replaced), so editing a user's source tree is safe — but any **newly created
path is root-owned**. That is why a tool that drops a scratch directory into the
project (rope's `.ropeproject/`) must be told not to: `Project(root,
ropefolder=None)`. Check for that class of artefact before shipping a
container-backed tool.
