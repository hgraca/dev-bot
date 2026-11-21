---
date: 2026-11-20
keywords: ["argocd", "retry-limit", "automated-sync", "self-heal"]
aliases: ["sync stopped retrying", "operation failed permanently", "stuck out of sync"]
trigger-on: ["argocd-automated-sync", "argocd-retry-limit"]
---

## Argo CD stops automated sync once the retry limit is exhausted

An Application with `syncPolicy.automated` and `retry.limit: 5` does not keep retrying. When the fifth attempt fails, `status.operationState.phase` settles on `Failed` and `selfHeal` no longer starts a new operation: the controller keeps reconciling — it still reports `OutOfSync` and updates `reconciledAt` — but never re-attempts the sync. The app sits half-applied until a human acts, with the resources from the waves that did run in place and the ones after the failure missing.

The trap is that the original cause has usually been fixed by the time you look — a missing Secret created, a quota raised — so nothing appears wrong and the app looks like it is merely waiting. `OutOfSync` plus `Healthy` is not "pending a reconcile": read `operationState.phase`, and if it is `Failed`, the app is stuck rather than progressing.

Clearing it needs a manual sync — `argocd app sync <app>`, or `kubectl -n argocd patch application <app> --type merge -p '{"operation":{"sync":{"prune":true}}}'` — and a fresh commit to the tracked branch also re-arms the retry budget. Watch the wave boundary when diagnosing: a failed wave 0 holds back every later wave, so a missing HTTPRoute that sits in wave 1 is a symptom of the earlier failure, not a second problem.
