---
date: 2026-09-20
keywords: ["tool-grades", "quadrants", "keep-improve-remove"]
see: ["ADRs/20260920000940-tool-grades-reporting-model-thresholds-and-quadrants.md", "PDRs/20260918122005-01-grade-tools-tool-evaluation-matrix.md"]
---

## The Tool Grades section answers three questions about the tool roster

Stakeholder intent (2026-09-19/20): the grades report exists to answer (1) which tools are the most useful we have, (2) which need improvement and which should be removed outright, and (3) for a tool used rarely but needed, whether it does the job when called. The quadrant grid carries (1) and (2) — `improve` means the capability is genuinely needed but the implementation disappoints, which is the opposite of a removal signal, so low use plus low grade is `unproven` rather than "remove". Requirement (3) is why a single usage x grade score was rejected: multiplying by usage scores a rarely-needed specialist near zero.

Stakeholder decisions taken with it: the grid puts high-grade x many-uses top-left; the table keeps `Avg` and `Uses` and gains `Min` and `σ`; `Min` and `σ` must say what to _do_ with them, not just what they are (a low `Min` means the tool has already failed once, a high `σ` means the average is not a promise); rows written before the actor column existed are backfilled `DevBot` while later blank actors stay blank; and the grades section is bound to the same `--days` and `--project` filters as the rest of the report.
