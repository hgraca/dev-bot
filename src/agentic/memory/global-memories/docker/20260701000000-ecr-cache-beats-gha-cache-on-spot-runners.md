---
date: 2026-07-01
keywords: ["docker", "github-actions", "ecr", "cache", "spot"]
trigger-on: ["docker-build-cache", "github-actions-cache", "docker-buildx-cache", "ecr-registry-cache"]
---

## Prefer ECR registry cache over GHA cache for Docker builds on AWS spot runners

When GH runners run on AWS spot instances in the same region as ECR, use `cache-from: type=registry,ref=<ecr-repo>:cache` + `cache-to: type=registry,ref=<ecr-repo>:cache,mode=max` instead of `type=gha`. GHA cache uses a REST API (slow, ~500MB per-entry cap, 10GB total limit, 7-day eviction, per-repo isolation) which is particularly bad for spot runners that lose local layer cache on every termination. ECR registry cache is unlimited, never evicted, shared across repos (critical for reusable workflows), and pulls at registry-native speed intra-region. Requires ECR auth already in the job (`aws-actions/amazon-ecr-login@v2`).
