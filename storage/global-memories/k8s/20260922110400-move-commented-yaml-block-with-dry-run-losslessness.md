---
date: 2026-09-22
keywords: ["k8s", "yaml", "config-editing", "refactor"]
trigger-on: ["yaml-block-move", "config-reorder", "commented-yaml-surgery"]
---

## Moving a commented config block: do it textually, dry-run it, then assert losslessness

Reordering blocks inside a heavily commented YAML config (Kubernetes manifests, Helm values) cannot be done with a YAML round-trip — parsing drops every comment. Do the surgery textually in Python: locate anchors by unique line content, extract operator/statement blocks by their `- id:` markers, and rebuild. Two guards make it safe. **Dry-run first**: write the result to a copy and diff it before touching the real file — on a real attempt the first build silently deleted a neighbouring block (`trace-parser`) because the reconstruction skipped the region between the insertion point and the removed block; the dry-run diff caught it, and it would otherwise have shipped as a silently dead operator. **Assert losslessness, not just plausibility**: normalise both versions (drop comments, blank lines and the lines you deliberately rewrote, sort) and diff them — 362/362 identical is proof the move changed nothing else, which a visual diff of a 465-line file is not. Also verify the *rendered* result, not only the source: comments vanish at render time, so a banner is invisible in the deployed ConfigMap while the element order is not.
