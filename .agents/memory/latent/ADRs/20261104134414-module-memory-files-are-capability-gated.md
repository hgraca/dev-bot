---
date: 2026-11-04
keywords: ["module memory", "active/modules", "aws module", "k8s module", "capability gate"]
aliases: ["aws.md", "k8s.md", "module memory file", "active memory"]
---

## Module memory files are written only when the capability they assert is wired

A module writes `<devbot_dir>/memory/active/modules/<module>.md` only when the project has actually
opted into, and the module has actually wired, the capability the file describes: `k8s.md` appears
only with a non-empty `kubectl` selection against a non-empty global catalogue, and `aws.md` only
when at least one selected connection has a valid name, is declared in the global catalogue, and a
harness that can start it is enabled. A file whose opening rule is "use X, never Y" must not be
written for a project where X does not exist — the agent would then refuse the fallback and have no
way in. The rule is recorded for module authors in `docs/create-a-module.md` § Module memory. The aws
module keeps a single file composed at init: the devbot-owned `src/agentic/aws/aws.md` (the MCP-only
rule, first) plus the upstream `storage/aws/rules/aws-agent-rules.md` that `install.sh` fetches,
joined through a temp file because `_devbot_write_module_memory` copies exactly one source. The old
per-rules file is no longer written: `_devbot_remove_module_memory` deletes its copies from both
`active/modules/` and the pre-modules `active/`, and the upstream file name survives only as the
install-time source. A missing `src/agentic/aws/aws.md` refuses the write, because a rules-only file
would leave upstream's "if unavailable, use the AWS CLI directly" uncontradicted.
