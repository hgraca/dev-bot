---
date: 2026-09-22
keywords: ["otel", "verification", "rollout", "gitops"]
trigger-on: ["otel-config-rollout-verify", "gitops-deploy-verification", "collector-rollout-detection"]
---

## A behaviour-preserving config rollout leaves no remote evidence — verify the bar you can actually meet

When a collector config change is designed to be behaviour-preserving (reordering operators, adding source guards that should not alter output), you can verify the *config* remotely but not the *rollout*: agent pods do not ship their own telemetry (their logs are excluded to avoid collection loops, and `otelcol_*` metrics are not exported here), and a Kubernetes rolling update **surges** — the new pod becomes ready before the old terminates — so there is no collection gap to detect. A per-node volume check on a steady high-volume container (e.g. `worker`, ~270 logs/s) is smooth across the whole window either way. So pick the honest verification split: with cluster access, prove the rollout directly (`kubectl get ds … -o jsonpath` for desired/ready/updated, the deployed ConfigMap's rendered content, pod ages); without it, prove the repo is pushed (`HEAD == origin/master`), prove **no regression** from post-window records, and say plainly that the fleet restart is unconfirmed — then point the reviewer at the ArgoCD app page rather than implying it was verified. Corollary: a behaviour-preserving change makes the local losslessness proof the strongest evidence available, so invest there (a normalised diff of every non-comment, non-guard line before/after) instead of in remote observation.
