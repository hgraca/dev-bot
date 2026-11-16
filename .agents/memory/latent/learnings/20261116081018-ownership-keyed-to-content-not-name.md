---
date: 2026-11-16
keywords: ["devbot", "mcp", "ownership", "manifest", "fingerprint"]
aliases: ["mcp-runtime ownership", "owned.harness record", "user manifest overwritten"]
see: ["ADRs/20261115130000-modules-publish-runtime-mcp-manifests.md"]
---

# Generated-file ownership must be keyed to content, not to a name

`_devbot_apply_runtime_mcps` first tracked ownership as a bare list of group names in `.owned.<harness>`. That record could not answer the question that matters — *is the file at this path still the one we wrote?* — so two paths were unsafe: the write path replaced a user's manifest that happened to share a group name (or one the user had edited after dev-bot generated it), and the retirement path deleted a user file created after the group had been retired, because the stale name was still recorded.

The rule: an ownership record must carry enough to recognise the content it owns. Here each line is `<group>\t<cksum fingerprint>` (`_devbot_file_fingerprint`, POSIX `cksum` — `sha256sum` is GNU-only). Both paths compare it — the write path refuses to overwrite a file whose fingerprint differs, and retirement deletes only on a match — and the record is rebuilt from what the pass actually wrote, so a claim is dropped as soon as the file stops matching. Same shape as the reset/asset rules: a name is not ownership; the artefact is.
