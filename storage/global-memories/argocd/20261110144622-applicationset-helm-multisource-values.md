---
date: 2026-11-10
keywords: ["argocd", "applicationset", "helm", "multi-source", "values"]
trigger-on: ["applicationset-helm-chart-app", "applicationset-files-generator"]
---

## Helm chart Applications in a directory-driven ApplicationSet need multi-source, not templated values

An ApplicationSet using a `directories` generator can only point an Application at a repository path (`spec.source.path`); a Helm chart has no path, so third-party charts cannot be first-class children of that pattern. The working shape is a second ApplicationSet with a `files` generator over `src/charts/<namespace>/<app>/app.yaml`, templating a two-source Application: the chart source (`repoURL` + `chart` + `targetRevision` + `helm.releaseName`) and a second source on the git repo with `ref: values`, whose `helm.valueFiles` is `$values/src/charts/<namespace>/<app>/values.yaml`. Do not try to inline the values: `values: '{{ .values }}'` collapses the multi-line scalar's newlines and produces invalid YAML, and `source: {{ .source | toYaml | nindent 8 }}` is not parseable template YAML at all (the template is a typed Application spec, not a text document). Keep the values as a real `values.yaml` — it also preserves the comments that a parse-and-re-emit through yq would drop. Two details that decide whether adoption is silent: the release name must stay byte-identical (a changed `releaseName` makes Helm see a brand-new release), and the file must carry an explicit `name:` because the path basename is `app.yaml`. Verified outcome: recreated chart Applications adopt running pods with zero restarts.
