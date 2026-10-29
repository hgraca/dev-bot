---
date: 2026-10-29
keywords: ["devbot", "kubectl", "kubeconfig", "credential-reference", "init"]
---

## Render the agent kubeconfig with credential references copied, not resolved

`src/agentic/k8s/init.sh` generates `~/.kube/devbot.yaml`, an exec credential wrapper and `~/.kube/devbot.env` from a `kubectl` node in the global config. Credential values are never resolved at init: the configured `${VAR}` reference is copied verbatim into the wrapper, so the shell resolves it when kubectl asks for a token. A datasource resolves its reference into a process environment at render time, which is safe because the consumer is a process; here the consumer is a file, so resolving early would write the secret to disk. For the same reason the config is not merged into `~/.kube/config`: mixing agent contexts into a human's admin kubeconfig is how a `--context` typo reaches production, so init writes a separate file plus an env file that exports `KUBECONFIG`. Init fails closed on anything that would break the boundary — a literal instead of a reference, an unset variable, a missing profile, or a profile whose `sts get-caller-identity` is not an `assumed-role` session (environment credentials overriding a plain-key profile would otherwise have the agent act as the source identity).
