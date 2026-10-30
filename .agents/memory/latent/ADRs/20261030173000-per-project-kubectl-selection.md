---
date: 2026-10-30
keywords: ["kubectl", "kubeconfig", "k8s", "global-config", "per-project"]
aliases: ["per project cluster access", "kubectl opt-in", "kubeconfig selection"]
see: ["ADRs/20261029170000-kubeconfig-references-copied-not-resolved.md"]
---

## Cluster access is chosen per project from a global catalogue

The global `kubectl` node stays the catalogue (`profile`, `credential_env`,
`clusters`); a project opts in by naming clusters in
`.devbot.project.jsonc::kubectl`, exactly as `datasources` and `aws_connections`
work. `k8s/init.sh` renders `~/.kube/devbot/<slug>.yaml` and `<slug>.env` per
project, sharing one `exec-credential.sh`. The slug is the project name plus the
first eight hex characters of the absolute path's SHA-256 — hashed through
`python3`, because macOS has no `sha256sum` — so two checkouts sharing a basename
cannot overwrite each other's kubeconfig.

Three consequences are deliberate. A selection that matches no catalogue entry
prunes the project's files **before** any environment check, and anything in the
existing kubeconfig outside the permitted set (selection ∩ catalogue) is revoked
at the same point, so a missing AWS CLI or a stale credential cannot preserve
access the project has dropped. A render that fails part-way keeps the file only
while every cluster in it is still permitted. The shared wrapper is never pruned
by one project's removal. The pre-selection machine-wide `~/.kube/devbot.yaml`
and `.env` are removed by the first init after upgrade, and only when the
kubeconfig references devbot's own wrapper.

Per-project files are ergonomics, not a security boundary: every generated file
is `0600` for the same user, and an agent with a shell can read another project's
file or repoint `KUBECONFIG`. What actually scopes access is IAM on the assumed
role.
