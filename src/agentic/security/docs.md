---
title: "Security"
description: "Security evaluation — static audit (STRIDE, OWASP Top 10, code review) and external web application pentest checks."
skills: ["audit-security", "pentest-external-webapp"]
---

Look at a web application the way an attacker would, and write down what it finds — from the inside
reading the code, and from the outside testing the running system.

## What it does

Ships two skills that answer different questions:

- `audit-security` — **the static counterpart.** STRIDE threat modelling, the OWASP Top 10, and
  PHP vulnerability assessment, against the source. For a security review, a threat model, or a
  vulnerability assessment of a web application.
- `pentest-external-webapp` — **the external evaluation.** The check list an external white-box,
  intrusive penetration test runs against an internet-facing web application: scope and
  authorisation first, then reconnaissance, scanner hypotheses, seven evidenced manual checks with
  explicit pass/fail criteria, CVSS 3.1 scoring in the report's finding format, and a regression
  pass over a prior engagement's findings. Ships a runnable, read-only probe script and the OWASP
  Web Security Testing Guide catalogue as references.

Neither replaces the other: a conclusion about an authorisation bug is far stronger with the code
read, and a header or port finding exists only at runtime.

## Configuration

No project configuration is required. The pentest skill's probe script needs `curl`; the open-port
check treats `80` and `443` as expected and everything else as a finding.

## See also

- [Architecture](/modules/agentic/architecture) — the security constraints `architecture-rules` carries
