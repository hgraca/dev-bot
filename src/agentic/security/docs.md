---
title: "Security"
description: "Security evaluation — static audit (STRIDE, OWASP Top 10, code review), external web application pentest checks, and the finding record both share."
commands: ["pentest-webapp"]
skills: ["audit-security", "pentest-external-webapp", "security-findings"]
---

Look at a web application the way an attacker would, and write down what it finds — from the inside
reading the code, and from the outside testing the running system.

## What it does

Two methods, and the vocabulary they share:

- `audit-security` — **the static counterpart.** STRIDE threat modelling, the OWASP Top 10, and
  PHP vulnerability assessment, against the source. For a security review, a threat model, or a
  vulnerability assessment of a web application.
- `pentest-external-webapp` — **the external evaluation.** The check list an external white-box,
  intrusive penetration test runs against an internet-facing web application: scope and
  authorisation first, then reconnaissance, scanner hypotheses, seven evidenced manual checks with
  explicit pass/fail criteria, and a regression pass over a prior engagement's findings. Ships a
  runnable, read-only probe script and the OWASP Web Security Testing Guide catalogue as references.
- `security-findings` — **the shared vocabulary.** One finding record, one severity scheme on
  CVSS v4.0, one status lifecycle, and one report shape, so a source finding and a runtime finding
  can sit in the same report and be compared. It carries no detection method: the two skills above
  supply that, and this one says how to write down what they found.

The two methods do not replace each other: a conclusion about an authorisation bug is far stronger
with the code read, and a header or port finding exists only at runtime. The third skill is what
keeps them from drifting into two dialects.

`/devbot:pentest-webapp <project>` runs the external evaluation against a
named project. It resolves the project — by name or path, asking when neither is given — loads that
project's memory and the skill, and then **stops at the authorisation gate the skill defines**: nothing
leaves the machine before every line of it is answered. The report is printed in the conversation and
offered to the project's `reference/` vault, never written silently.

## Configuration

No project configuration is required. The pentest skill's probe script needs `curl`; the open-port
check treats `80` and `443` as expected and everything else as a finding.

## Tooling

`scripts/tooling.sh` is one façade over four delivery backends, so the skills name a tool and never
learn whether it is a local binary, a `uvx` invocation, a container or a system package:

| Backend  | Tools                               | Installed how                                 |
| -------- | ----------------------------------- | --------------------------------------------- |
| `go`     | `nuclei`, `ffuf`, `gitleaks`        | `go install`, version recorded after the fact |
| `uvx`    | `semgrep`, `bandit`, `sqlmap`       | resolved per call — nothing is installed      |
| `docker` | `zap`, `trivy`, `metasploit`        | `docker pull`, run with `--rm` and no network |
| `system` | `nmap`, `tcpdump`, `hydra`, `nikto` | your package manager — never auto-installed   |

`tooling.sh check` prints what is present; a check whose tool is absent is recorded as skipped, never
as passed. Provisioning reaches the network, so `devbot install` only reports unless
`SEC_TOOLS_AUTO_INSTALL=1` is set, while `devbot update` runs the install pass. Binaries and the
version record live under `storage/security-tools/`, outside the committed tree.
`SEC_TOOLS_DOCKER_NETWORK` opts a container run out of its default `--network none` when the check
must reach the target.

## See also

- [Architecture](/modules/agentic/architecture) — the security constraints `architecture-rules` carries
