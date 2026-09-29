---
name: devbot:forensics-report
description: Generate a behavioral forensics report for a project — mine its history into one Markdown file, then add your own refactoring and bus-factor recommendations
---

Generate a forensics report for a project, and add your own reading of it.

The project path is the argument (`$1`). When it is absent, use the current project.

## 1. Ask for the time window

Never guess it. Ask the user which period to analyse, and offer **the last calendar month**
as the default (the tool's own window). Bounds are `YYYY-MM-DD` in **UTC**; `--all` mines the
whole history instead and cannot be combined with a bound.

## 2. Generate the report

Load the `devbot:forensics` context skill, then run:

```
bash "$DEV_BOT_ROOT/src/agentic/forensics/tools/forensics.sh" run "<project>" \
  --since <YYYY-MM-DD> --until <YYYY-MM-DD> \
  --out "<project>/.forensics/report-<since>_<until>.md"
```

`run` mines the history and writes **one** self-contained Markdown file: every view, a Data-quality
block, commit activity, PR activity and an empty `## Analysis & recommendations` section. The
`.forensics/` directory self-ignores, so the report is never committed.

Add `--trends`, `--defects <csv>` or `--modules name=prefix,...` when the user wants those sources —
each adds a section the Data-quality block otherwise reports as absent. PR activity needs an
authenticated `gh`; without one the report says so and still renders.

## 3. Fill in the analysis

Read the report, then replace the placeholders under `## Analysis & recommendations`. Ground every
claim in a figure the report actually contains — name the file, the signal and the number. Generic
advice ("write more tests") is not analysis and must not appear.

- **Refactoring targets** — from Hotspots, Debt priority and Complexity trends: which files, on which
  signal (complexity × change rate, complexity still growing), in what order. Say what makes each one
  worth attention now.
- **Bus factor & knowledge sharing** — from Ownership, Ownership concentration, Unit ownership risk and
  the bus-factor line: which files and units are single-owner, whom the bus factor constrains, and the
  concrete mitigation (pairing, review rotation, secondary owners, documentation).
- **Limits** — restate every source the Data-quality block reports absent, so the reader knows what
  this analysis could not see.

## 4. Report back

Give the user the file path and a short summary of the findings. Make no change to version control.

## Notes

- `$DEV_BOT_ROOT` is exported by the harness. If it is unset, fall back to the script inside the
  dev-bot checkout.
