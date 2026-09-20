---
date: 2026-09-16
keywords: ["mongo", "kernel-6.19", "tcmalloc", "service-container"]
trigger-on: ["mongo-container-wont-start", "mongo-connection-refused"]
---

## MongoDB 8.0.5+ cannot start on Linux kernels 6.19 and newer

On a host or CI runner whose Linux kernel is 6.19 or newer, a MongoDB container at 8.0.5 or above aborts during startup with a fatal `CONTROL` log line reading "MongoDB cannot start: Linux kernel versions 6.19 and newer has a known incompatibility with this version of MongoDB" (SERVER-121912) and exits immediately. Whatever connects then reports `connection refused` on the mapped port - a symptom that looks like a networking or config bug, not an image incompatibility, which sends diagnosis down the wrong path. The cause is a TCMalloc/rseq ABI violation (`GLIBC_TUNABLES=glibc.pthread.rseq=0` is baked into the images); the 6.x and 7.x lines and 8.0.0-8.0.4 are unaffected. Recognise it from the _service container's own startup log_ in the job output rather than the test output, and confirm it is not your change by checking whether the same job also fails on the default branch. Bumping the image does not help - 8.0.30 and 8.0.32 both still refuse because the narrowing (SERVER-125742) never shipped in the 8.0 line; per MongoDB's 8.0 release notes the remedy is the kernel (<= 6.18, or >= 7.0.14). So the cleanest CI fix is to pin the _runner image_ to one with an older kernel - e.g. RunsOn's `image=ubuntu22-full-x64` reports 6.8.0-1063-aws and runs mongo:8 happily. Falling back to an unaffected MongoDB major (6.x/7.x) or passing `GLIBC_TUNABLES=glibc.pthread.rseq=1` also work.
