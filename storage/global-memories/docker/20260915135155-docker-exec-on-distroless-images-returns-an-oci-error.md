---
date: 2026-09-15
keywords: ["docker", "docker-exec", "distroless", "printenv", "verification"]
trigger-on: ["docker-exec-distroless", "docker-inspect-config-env"]
---

## `docker exec` on a distroless image returns an OCI error that reads like command output

On an image with no shell and no coreutils (distroless — e.g. `signoz/signoz-mcp-server`), any `docker exec <c> <binary>` fails at the runtime level rather than inside the container:

```
OCI runtime exec failed: exec failed: unable to start container process:
exec: "printenv": executable file not found in $PATH
```

This message goes to the command's output stream, so a naive check reads it as data. Real failure mode observed: `docker exec <c> printenv SIGNOZ_API_KEY | awk '{print length($0)}'` reported a plausible non-empty value, and `grep -q .` "confirmed" the variable was set — the "value" was the error text.

`CMD`-style probes that rely on `sh -c` fail the same way (`exec: "sh": not found`), which also means **container healthchecks cannot use a shell** on such images — `HEALTHCHECK CMD-SHELL` has nothing to run.

To inspect a container's configuration on a distroless image, read it from the container metadata instead:

```sh
docker inspect <c> --format '{{range .Config.Env}}{{println .}}{{end}}'
```

Two habits worth keeping: check whether an image can run a probe before designing a healthcheck around one (`docker exec <c> sh -c 'echo ok'`), and never accept a `docker exec` result as evidence without confirming the command actually executed — a non-empty output string is not proof of a successful exec.
