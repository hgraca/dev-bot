---
date: 2026-09-17
keywords: ["docker", "podman-desktop", "container", "flatpak", "tar.gz"]
---

## Podman Desktop publishes no .deb — install via flatpak or GitHub tar.gz

Podman Desktop (github.com/podman-desktop/podman-desktop) publishes **no `.deb`** in its GitHub releases — only `.dmg`/`.exe`/`.zip`/`.flatpak`/`.tar.gz` (versioned assets like `podman-desktop-1.29.3-x64.tar.gz`; there is no fixed-name "latest" asset). SEO "install podman-desktop ubuntu .deb" articles claiming a `.deb` exists are wrong. Options: flatpak (`flatpak install flathub io.podman_desktop.PodmanDesktop`, upstream-recommended) or the x64 `.tar.gz`. The tarball extracts to a `podman-desktop-<ver>-x64/` directory (Electron binary plus `libEGL.so`/`resources/`/`locales/` that must stay together) — symlink its `podman-desktop` binary into `~/.local/bin` and keep the whole dir, don't copy the binary alone. Resolve the latest URL via the GitHub API (`api.github.com/repos/podman-desktop/podman-desktop/releases/latest`, grep `browser_download_url` for `-x64.tar.gz`). No icon file ships in the tarball (the icon is embedded in the binary).
