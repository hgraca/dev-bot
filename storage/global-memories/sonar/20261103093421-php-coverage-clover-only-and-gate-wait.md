---
date: 2026-11-03
keywords: ["sonar", "coverage", "clover", "qualitygate-wait", "php"]
aliases: ["sonar coverage does not contain any record", "cobertura rejected"]
trigger-on: ["sonar-php-coverage"]
---

## SonarQube PHP coverage is Clover-only, and the gate reads stale analyses

`sonar.php.coverage.reportPaths` accepts **Clover XML only** (SonarQube's PHP coverage docs). A Cobertura report produced by phpunit/ParaTest (`--coverage-cobertura`) is parsed as Clover, produces "Coverage report does not contain any record", and the quality gate reads 0% — while Codecov shows healthy coverage from the very same file, which makes the failure look like a Sonar bug rather than a format mismatch. Generate Clover (`--coverage-clover`) and strip the absolute workspace prefix before scanning (`sed -i "s#${GITHUB_WORKSPACE}/##g"` on both the coverage and JUnit reports). Separately, querying `/api/qualitygates/project_status` immediately after a scan returns the **previous** analysis, so a fixed pipeline keeps reporting the old failure on every push; set `-Dsonar.qualitygate.wait=true` (`sonar.qualitygate.timeout`, default 300s) so the scanner waits for processing and exits non-zero on a red gate.
