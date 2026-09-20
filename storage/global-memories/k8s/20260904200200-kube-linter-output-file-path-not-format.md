---
date: 2026-09-04
keywords: ["k8s", "kube-linter", "--output", "--format", "lint"]
---

## kube-linter lint: `--output` is an output FILE path, not a format selector — JSON on stdout is `--format json`

`kube-linter lint <files> --output json` writes the report to a file literally
named `json` in the working directory (in the default plain format) and leaves
stdout empty — `--output` is a repeatable output-file-path flag that must pair
with a matching `--format`. To get the JSON report on stdout use
`kube-linter lint <files> --format json` and omit `--output`. Gotcha observed
in a wrapper that intended `--output json` as a format choice and silently
sprinkled stray `json` files into every project it ran in.
