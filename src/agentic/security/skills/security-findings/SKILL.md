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

| Field                   | Required        | Content                                                                                                                                                                                             |
| ----------------------- | --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `**ID:**`               | always          | `<report>.<n>`. Stable for the life of the finding — a re-test reuses it.                                                                                                                           |
| `**Title:**`            | always          | One line naming the defect class, not the endpoint.                                                                                                                                                 |
| `**Severity:**`         | always          | `Critical` / `High` / `Medium` / `Low` / `Informational`.                                                                                                                                           |
| `**CVSS:**`             | always          | The `CVSS:4.0/` vector, the score a 4.0 calculator returns, and the designation — `CVSS-B`, `CVSS-BT`, `CVSS-BE` or `CVSS-BTE` — or `none` for an `Informational` finding. See [Scoring](#scoring). |
| `**Tier:**`             | always          | `read-in-source` / `observed` / `reproduced`. See [Evidence tiers](#evidence-tiers).                                                                                                                |
| `**Finding:**`          | always          | What is wrong, and the observation that proves it.                                                                                                                                                  |
| `**Result:**`           | always          | What an attacker gains **and what limited it**. A mitigating control that held belongs here, not in a footnote.                                                                                     |
| `**Evidence:**`         | always          | The observation: request/response excerpt, probe output, or `file:line`. Not a summary of one.                                                                                                      |
| `**Status:**`           | always          | The lifecycle state. See [Lifecycle](#lifecycle).                                                                                                                                                   |
| `**Discovered:**`       | always          | The commit the finding was established against, plus the date.                                                                                                                                      |
| `**Location:**`         | source          | `path/to/file.ext:line`, and the enclosing symbol when one exists.                                                                                                                                  |
| `**Targets:**`          | runtime         | The exact URLs or hostnames tested. Never a pattern, never a sibling host inferred from one.                                                                                                        |
| `**Proof of concept:**` | when one exists | Numbered steps or the exact request sequence that demonstrates the finding.                                                                                                                         |
| `**Recommendation:**`   | always          | The specific fix. An allowlist over a blocklist; least privilege over review.                                                                                                                       |
| `**References:**`       | always          | `CWE-nnn`, the OWASP category as `A0n:2025`, and the ASVS requirement when one applies.                                                                                                             |
| `**Coverage basis:**`   | always          | Which check, tool or phase produced this — so a reader can tell detection from inference.                                                                                                           |

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

**Threat metrics.** `E` is **Exploit Maturity** — what is known about exploitation in general:
`A` attacked, `P` proof-of-concept, `U` unreported. An absent `E` scores as `E:A`, the worst case,
which is the right assumption for a finding nobody has tested in the field.

`E` is **not** a record of whether this target's control stopped a payload. An attempt that failed
says nothing about how mature the exploit is, and setting `E:U` to mean "we tried it and it did not
work" mis-scores the finding — in whichever direction it happens to sit.

A control that held belongs in the impact metrics:

- **In the implementation** — a prepared statement, an allowlist in the code — the base impact
  already reflects it, because the weakness is not there to find.
- **In the environment** — a WAF rule, a network boundary, a deployment setting — lower the modified
  impact metric it defuses (`MVC`/`MVI`/`MVA`, and `MSC`/`MSI`/`MSA` for a subsequent system), and
  keep the observation in `Result`.

State the designation so a reader knows which question was answered: `CVSS-B` (base only), `CVSS-BT`
(plus threat), `CVSS-BE` (plus environmental), `CVSS-BTE` (both).

Qualitative bands, identical across the two skills:

| Band     | Score    |
| -------- | -------- |
| Critical | 9.0–10.0 |
| High     | 7.0–8.9  |
| Medium   | 4.0–6.9  |
| Low      | 0.1–3.9  |
| None     | 0.0      |

`Informational` is not a CVSS band. It marks something recorded for the reader's attention with no
security impact, and such a finding carries no vector at all: `**CVSS:**` reads `none`. That and a
v4.0 vector are the only two values the field may hold.

Score the exploitable reality, not the worst case — which in v4.0 means setting the metric that
represents it, not annotating the prose beside a score that ignores it.

## Lifecycle

```
open ──▶ confirmed ──▶ mitigated ──▶ open   (a re-test found it again)
  │           │
  │           ├──▶ accepted_risk
  │           └──▶ false_positive   (refuted at source tier only)
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
- **A `read-in-source` confirmation may be flipped.** That confirmation was also an argument — a
  traced path, not an observation — so the refutation outranks it and `confirmed → false_positive`
  is the correct edge. The tier is what decides which of the two rules applies.
- **A re-test that finds it again reopens it.** `mitigated → open`, with the re-test's verdict
  recorded. A mitigation that did not hold is a new fact about the same finding, not a new record —
  and a finding that keeps coming back is worth more than one that was once closed.
- **`mitigated` requires the observable, not the fix.** A merged commit, a code comment, or a
  stated intention is not evidence; the check that demonstrated the finding must now pass.
- **`accepted_risk` is a human decision.** An assessor may propose it; only the owner accepts it,
  and the acceptance carries a name and a review date.
- **Re-tests reuse the `ID`.** A prior finding's new verdict is an update to its record, not a new
  record — otherwise a regression pass cannot report "still open".

### Three vocabularies, three axes

They answer different questions and never substitute for one another:

| Vocabulary         | Question it answers                  | What it sets                           |
| ------------------ | ------------------------------------ | -------------------------------------- |
| Status             | Where is this record now?            | `Status`                               |
| Re-audit verdict   | What did a regression pass conclude? | `Status`, via a re-test                |
| Refutation verdict | What did the second reader conclude? | `Status`, if it rejects at source tier |

## The store

A record that lives only in a report is a paragraph. The store is what makes it do work:
`<devbot_dir>/memory/latent/security/findings.jsonl` in the project being reviewed, one JSON object
per line mirroring the record's fields.

| Field        | Shape                                                        |
| ------------ | ------------------------------------------------------------ |
| `id`         | the record's `ID`                                            |
| `title`      | one line                                                     |
| `severity`   | `Critical` / `High` / `Medium` / `Low` / `Informational`     |
| `status`     | the lifecycle state                                          |
| `tier`       | `read-in-source` / `observed` / `reproduced`                 |
| `discovered` | the commit the finding was established against               |
| `location`   | `{"file": …, "line": …, "symbol": …}` — source findings only |
| `targets`    | array of URLs — runtime findings only                        |
| `cvss`       | the vector and score, when one was computed                  |

The module's CLI owns the file — `$DEV_BOT_ROOT/src/agentic/security/scripts/findings.sh`:

- `add` — one JSON object on stdin; validates the required fields and the three vocabularies, and
  refuses a duplicate `ID`.
- `update` — replaces a record by `ID`. This is the re-test path: the contract reuses the `ID` rather
  than minting a new record, and `add` refuses a duplicate.
- `check` — validates every record and summarises by status.
- `list --file <path>` — the advice surface: what we already know about this file, before editing it.
- `stale` — findings that predate the file they describe.

Write the record to the store **and** to the report. A finding in the report but not the store is one
nobody reads again; in the store but not the report is one the reader never sees.

## The gate

`findings.sh gate` answers a diff against the store, and its exit code is the answer:

| Exit | Verdict  | Means                                                     |
| ---- | -------- | --------------------------------------------------------- |
| 0    | `PASS`   | every check ran and nothing known intersects the change   |
| 1    | `REVIEW` | known findings touch the change, or a check could not run |
| 2    | `BLOCK`  | an open High/Critical finding sits on the changed lines   |
| 3    | usage    | the call was wrong; nothing was checked                   |

Three relationships — and this is why a changed _caller_ matters:

- **`direct`** — the finding's line falls in a changed hunk, with the two-line slack a hunk boundary
  needs.
- **`unrelated_in_file`** — the finding is in a changed file but outside the modified lines: debt you
  are now working next to.
- **`caller_radius`** — a changed file calls the finding's symbol. Without a parser this is a
  call-site match; `codebase-memory.detect_changes` gives the precise radius when it is available.

**It fails closed.** A missing store, an unparseable store and an empty change set each answer
`REVIEW`, never `PASS`. `PASS` means "every check ran and found nothing", not "this change is secure".

```bash
git diff --cached | findings.sh gate      # pre-commit
findings.sh gate --base origin/main       # CI
```

A `BLOCK` is a reason to fix the finding, or to mark it `false_positive` with evidence — never a
reason to regenerate the store.

## Report shape

One shape for both skills, sections in this order:

1. **Scope and basis** — what was assessed, what was excluded, and why. For a runtime engagement,
   the authorisation's reference belongs in the first line.
2. **Coverage** — what was examined, and what was not. Name the checks that were skipped and the
   reason (tool absent, not applicable, outside scope). A clean section that omits this is
   indistinguishable from a partial one.

   The security module's `$DEV_BOT_ROOT/src/agentic/security/scripts/tooling.sh check` prints which
   tools are present at the moment of the review, with the version this machine has where one was
   recorded. **Record that output in the report.** A check whose tool was absent is recorded
   `skipped: tool absent` — the sentence a reader needs, and the one a tidy table quietly drops — and
   the version lines are what let a later reader tell whether a re-run used the same scanner that
   produced the evidence.

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
- **A finding is not final until refuted.** `@critic` produces the verdict and `@security` folds it
  in; the orchestration route is the security-refutation row in `teamlead`'s delegation table. This
  skill fixes only the vocabulary: `uphold`, `downgrade`, `reject`, `unverifiable`.

## See also

- `devbot:audit-security` — the source-side method that produces records with a `Location`.
- `devbot:pentest-external-webapp` — the runtime method that produces records with `Targets`.
- `references/example.md` — one worked record and one worked report.
