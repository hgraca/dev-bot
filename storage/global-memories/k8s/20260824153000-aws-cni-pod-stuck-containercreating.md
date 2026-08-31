---
date: 2026-08-24
keywords: ["k8s", "eks", "aws-cni", "aws-node", "ContainerCreating"]
trigger-on: ["pod-stuck-containercreating", "aws-node-crashloop", "failedcreatepodsandbox"]
---

## Pod stuck ContainerCreating — FailedCreatePodSandBox dial 127.0.0.1:50051 = aws-node CNI crashlooping on that node

On EKS, a pod stuck in `ContainerCreating` whose `describe` shows `Failed to create pod sandbox ... plugin type="aws-cni" ... dial tcp 127.0.0.1:50051: connect: connection refused` is NOT an app/config problem — the aws-node CNI daemonset pod on that node is crashlooping (its local gRPC endpoint 127.0.0.1:50051 is down). Check `kubectl get pods -n kube-system -l k8s-app=aws-node -o wide` and look for a high restart count on the node the pod is scheduled to (the node still reports `Ready`, so it doesn't get cordoned). This can leave old pods un-terminated (rolling update stuck) and manifests as a few isolated `ContainerCreating` pods while all others run fine. Fix is at the node/CNI level, not the workload.
