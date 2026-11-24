---
name: devbot:security-findings
description: "Use when recording, scoring, re-checking or reporting a security finding. Load it when devbot:audit-security or devbot:pentest-external-webapp produces findings, and when reading or re-testing a finding record an earlier session wrote."
---

# Security Finding Records

One vocabulary for both security skills: one record, one severity scheme, one status lifecycle, one
report shape. This skill holds no detection method — `devbot:audit-security` reviews source and
`devbot:pentest-external-webapp` tests a running system, and each says what to look for. This one
says how to write down what was found, so a source finding and a runtime finding can sit in one
report and be compared.

Load it before the first finding is written, not after: the record decides what must be observed,
and retro-fitting evidence is how findings become assertions.

## When to Apply

- A `devbot:audit-security` or `devbot:pentest-external-webapp` run has produced findings
- Re-testing or re-auditing a prior report — reading records an earlier session wrote
- Deciding whether a finding is confirmed, and whether it may be closed
- Writing the final report

## The record

One record per finding. Fields marked **always** are required; the rest depend on the finding's
basis.

| Field                   | Required        | Content                                                                                                         |
| ----------------------- | --------------- | --------------------------------------------------------------------------------------------------------------- |
| `**ID:**`               | always          | `<report>.<n>`. Stable for the life of the finding — a re-test reuses it.                                       |
| `**Title:**`            | always          | One line naming the defect class, not the endpoint.                                                             |
| `**Severity:**`         | always          | `Critical` / `High` / `Medium` / `Low` / `Informational`.                                                       |
| `**CVSS:**`             | always          | The `CVSS:4.0/` vector and the score a 4.0 calculator returns. See [Scoring](#scoring).                         |
| `**Tier:**`             | always          | `read-in-source` / `observed` / `reproduced`. See [Evidence tiers](#evidence-tiers).                            |
| `**Finding:**`          | always          | What is wrong, and the observation that proves it.                                                              |
| `**Result:**`           | always          | What an attacker gains **and what limited it**. A mitigating control that held belongs here, not in a footnote. |
| `**Evidence:**`         | always          | The observation: request/response excerpt, probe output, or `file:line`. Not a summary of one.                  |
| `**Status:**`           | always          | The lifecycle state. See [Lifecycle](#lifecycle).                                                               |
| `**Discovered:**`       | always          | The commit the finding was established against, plus the date.                                                  |
| `**Location:**`         | source          | `path/to/file.ext:line`, and the enclosing symbol when one exists.                                              |
| `**Targets:**`          | runtime         | The exact URLs or hostnames tested. Never a pattern, never a sibling host inferred from one.                    |
| `**Proof of concept:**` | when one exists | Numbered steps or the exact request sequence that demonstrates the finding.                                     |
| `**Recommendation:**`   | always          | The specific fix. An allowlist over a blocklist; least privilege over review.                                   |
| `**References:**`       | always          | `CWE-nnn`, the OWASP category as `A0n:2025`, and the ASVS requirement when one applies.                         |
| `**Coverage basis:**`   | always          | Which check, tool or phase produced this — so a reader can tell detection from inference.                       |

Exactly one of `Location` and `Targets` is present, matching the basis: a source finding has a
location, a runtime finding has targets.

## Evidence tiers

The tier states how the finding was established, which is what a reader needs before trusting the
severity.

- **`read-in-source`** — the defect is visible in the code, and the path from an untrusted boundary
  to the sink was traced. The strongest a source-only review can reach.
- **`observed`** — a response, header, port, or output was seen. The system behaved as described.
- **`reproduced`** — the effect was demonstrated: a payload worked, a test failed in the way the
  finding claims.

A finding whose tier is `read-in-source` cannot claim the impact of one that was `reproduced`
without saying so in `Result`. Reachability you did not trace is a candidate, not a finding.

## Scoring

Score with **CVSS v4.0** — <https://www.first.org/cvss/v4.0/specification-document>. v3.1 is
archived; never emit a 3.1 vector.

Build the **Base** metrics:

| Group             | Metrics                                                            |
| ----------------- | ------------------------------------------------------------------ |
| Exploitability    | `AV` (N/A/L/P), `AC` (L/H), `AT` (N/P), `PR` (N/L/H), `UI` (N/P/A) |
| Vulnerable system | `VC`, `VI`, `VA` (H/L/N)                                           |
| Subsequent system | `SC`, `SI`, `SA` (H/L/N)                                           |

v4.0 has **no `Scope` metric** — it is replaced by the vulnerable-system (`VC/VI/VA`) and
subsequent-system (`SC/SI/SA`) split. `AT` (Attack Requirements) carries preconditions such as a
race window or a man-in-the-middle position that v3.1 forced into `AC`.

Never compute the score by hand. The v4.0 model is non-linear and no arithmetic over the metrics
reproduces it — feed the vector to a calculator
(<https://www.first.org/cvss/calculator/4.0>) and record what it returns.

**Leave Threat and Environmental metrics unset** unless the deployment is genuinely known. A
source finding usually cannot observe them. The evidence tier is what tells a reader the score is a
base score, not a tailored one.

Qualitative bands, unchanged from 3.1 and identical across the two skills:

| Band          | Score    |
| ------------- | -------- |
| Critical      | 9.0–10.0 |
| High          | 7.0–8.9  |
| Medium        | 4.0–6.9  |
| Low           | 0.1–3.9  |
| Informational | Unscored |

Score the exploitable reality, not the worst case. A control that held during the assessment is
named in `Result` rather than silently raising the score, and an information disclosure with no
direct compromise is `Informational` — and still belongs in the report.

## Lifecycle

```
open ──▶ confirmed ──▶ mitigated
  │           │
  │           └──▶ accepted_risk
  └───────────────▶ false_positive
```

| State            | Means                                                                                            |
| ---------------- | ------------------------------------------------------------------------------------------------ |
| `open`           | Recorded, not yet validated. Every new finding starts here.                                      |
| `confirmed`      | Validated with evidence at the tier it claims.                                                   |
| `mitigated`      | A fix landed and the observable that demonstrated the finding no longer appears.                 |
| `false_positive` | Refuted, with the evidence that refutes it.                                                      |
| `accepted_risk`  | Understood and deliberately not fixed — records **who** accepted it and **when it is reviewed**. |

Rules that do not bend:

- **A dismissal never erases an observed verdict.** `observed` and `reproduced` confirmations are
  evidence; `false_positive` is an argument. A finding confirmed at those tiers may be annotated or
  superseded, never flipped to `false_positive`. Refuting an `observed` finding means naming what
  the observation actually was — usually a new record with a different claim.
- **`mitigated` requires the observable, not the fix.** A merged commit, a code comment, or a
  stated intention is not evidence; the check that demonstrated the finding must now pass.
- **`accepted_risk` is a human decision.** An assessor may propose it; only the owner accepts it,
  and the acceptance carries a name and a review date.
- **Re-tests reuse the `ID`.** A prior finding's new verdict is an update to its record, not a new
  record — otherwise a regression pass cannot report "still open".

## Report shape

One shape for both skills, sections in this order:

1. **Scope and basis** — what was assessed, what was excluded, and why. For a runtime engagement,
   the authorisation's reference belongs in the first line.
2. **Coverage** — what was examined, and what was not. Name the checks that were skipped and the
   reason (tool absent, not applicable, outside scope). A clean section that omits this is
   indistinguishable from a partial one.

   The security module's `src/agentic/security/scripts/tooling.sh check` prints which tools are
   present at the moment of the review. A check whose tool was absent is recorded
   `skipped: tool absent` — the sentence a reader needs, and the one a tidy table quietly drops.

3. **Findings** — by severity, each in the record shape.
4. **Refutation** — per finding, the verdict of the separate pass and what it rested on.
5. **Summary** — counts by severity, the top three by score, quick wins, and systemic issues (a
   pattern needing an architectural change rather than a point fix).
6. **Positive findings** — what the codebase or deployment does well. A report that only lists
   defects cannot be used to decide what to leave alone.

Group by defect class: twenty instances of one pattern are one finding with an inventory, not twenty
records.

## Rules

- **No evidence, no finding.** An observation you cannot cite is a hypothesis; record it as one or
  leave it out.
- **State the tier honestly.** An over-claimed tier is worse than a low one — it propagates into the
  severity and then into someone's prioritisation.
- **Never restate the method.** Detection belongs to the skill that performed it; a report cites the
  check, not its procedure.
- **A finding is not final until refuted.** See `devbot:audit-security` and
  `devbot:pentest-external-webapp` for who runs the refutation pass and in what order; this skill
  only fixes the verdict vocabulary: `uphold`, `downgrade`, `reject`, `unverifiable`.

## See also

- `devbot:audit-security` — the source-side method that produces records with a `Location`.
- `devbot:pentest-external-webapp` — the runtime method that produces records with `Targets`.
- `references/example.md` — one worked record and one worked report.
