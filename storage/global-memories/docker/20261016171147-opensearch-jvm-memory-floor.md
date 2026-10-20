---
date: 2026-10-16
keywords: ["docker", "opensearch", "jvm", "heap", "memory"]
---

## JVM `-Xmx` caps heap only — OpenSearch total RSS can't be set to 250 MB

A JVM process's `-Xmx` limits only the heap; metaspace, JIT code cache, thread stacks and direct buffers add ~300–500 MB on top, so an OpenSearch target of 250 MB total is unreachable (even `-Xmx256m` lands ~500–600 MB RSS and likely OOMs on first query). The dev-footprint cap is the pair `OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m -XX:-AlwaysPreTouch` (last-wins over `jvm.options`' `-Xmx1g`; `-XX:-AlwaysPreTouch` stops the full heap being committed at boot) plus `DISABLE_PERFORMANCE_ANALYZER_AGENT_CLI=true` (stops the in-process 512 MB perf-analyzer agent) — this idles single-node OpenSearch around ~600 MB instead of ~1.1 GB. After editing compose, recreate the container (`docker compose up -d <svc>`); a running container keeps the old flags until recreated.
