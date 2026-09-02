---
date: 2026-09-02
keywords: ["test-project", "harness", "macos", "dockurr", "devbot"]
see: ["global/docker/20260902204416-dockurr-macos-qemu-vm-not-container.md", "learnings/20260902204416-oc-cc-harness-tests-test-project.md"]
---

## Rejected: --macos flag for oc/cc harness tests via dockurr/macos

The stakeholder asked for a `--macos` flag on `tests/test-project/test-oc.sh` / `test-cc.sh` to run the opencode/claudecode harness tests on macOS, initially expecting a drop-in swap of the Linux container. On investigating dockurr/macos as the vehicle, the idea was **rejected** ("let's forget about this idea, I thought it would be simpler").

Rationale: dockurr/macos is not a container image swap — it is a QEMU/KVM VM wrapped in a container. There is no automated macOS install (first boot requires a manual GUI install through the web viewer: erase disk → reinstall → region → create user account), `docker exec` never reaches the macOS guest, and command execution requires SSH or VNC with extra port mapping and Remote Login setup. That is a fundamentally different, much heavier execution topology than the current `docker run ... devbot-test` ubuntu flow, so the inner scripts (`test-reinit.sh` apt paths, `/home/ubuntu`, `--network host`, `/app` bind mount) do not transfer as-is. Net-new macOS-VM infra would be needed in the repo for little gain over the existing Linux-container tests.

Decision: the oc/cc harness tests stay Linux-container-only for now. If real-macOS validation of devbot is ever needed (e.g. for the mac-host support work on `feature/mac-fixes-local-external-modules`), revisit via a persistent native VM or CI runner rather than dockurr-style docker virtualization.
