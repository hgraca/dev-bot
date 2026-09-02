---
date: 2026-09-02
keywords: ["docker", "dockurr", "macos", "qemu", "kvm"]
trigger-on: ["docker-macos-container", "dockurr-macos", "macos-in-docker"]
---

## dockurr/macos is a QEMU VM in a container, not a macOS container image

"macOS in a Docker container" (dockurr/macos, successor to docker-osx) does **not** behave like a normal container: the image wraps a QEMU/KVM VM, so macOS runs as a full guest, not a container process. Consequences that break "just swap the image" assumptions:

- **No automated install.** Unlike dockur/windows, first boot is a manual GUI install through the web viewer at port 8006: erase the VirtIO disk in Disk Utility, reinstall macOS, pick region/language, create a user account. Count on ~1 manual bootstrap per VM.
- **`docker exec` never reaches macOS.** It lands in the Linux/QEMU wrapper container. Commands inside macOS need SSH (map e.g. `-p 2222:22`, then enable Remote Login once inside the GUI) or manual VNC/web-viewer interaction.
- **Host files reach the guest via 9p**, not a bind mount: mount a host dir at `/shared` and run `sudo mount_9p shared` inside macOS.
- **Hard requirements**: Linux host with `/dev/kvm` (Docker Desktop on macOS/Windows provides no KVM and is unsupported), AVX2 CPU, ≥4 GB RAM, ≥32 GB free disk; Intel CPUs give much better compatibility than AMD (AMD: avoid multiple cores / >8 GB RAM early, install may freeze).
- **Disk persists** in a `/storage` volume; the VM is stateful, not ephemeral like `--rm` containers.

Design consequence: using dockurr/macos as a "macOS test runner" means orchestrating a stateful VM with a manual GUI bootstrap + SSH — a different execution topology, not a container-image drop-in.
