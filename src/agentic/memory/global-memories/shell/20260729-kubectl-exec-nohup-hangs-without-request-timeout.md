---
date: 2026-07-29
keywords: ["kubectl", "shell", "nohup", "request-timeout"]
trigger-on: ["kubectl-exec-hang", "nohup-kubectl", "kubectl-timeout"]
---

## kubectl exec in nohup scripts hangs without --request-timeout=0 when API session expires

When running kubectl exec inside a nohup/detached shell script against a remote cluster, the kubectl API session can expire after hours of inactivity. Without `--request-timeout=0`, kubectl exec hangs indefinitely waiting for a response that will never come. This causes scripts to silently freeze — no error, no exit, just stuck. Fix: always pass `--request-timeout=0` to every kubectl exec call in scripts, not just long-running commands. The default kubectl request timeout is 0 in newer versions but the connection can still be dropped by proxies or network layers.
