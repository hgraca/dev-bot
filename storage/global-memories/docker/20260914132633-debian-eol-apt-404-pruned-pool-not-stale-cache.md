---
date: 2026-09-14
keywords: ["docker", "debian", "apt", "end-of-life", "base-image"]
trigger-on: ["dockerfile-base-image-eol", "apt-get-install-404"]
---

## Debian EOL: apt 404s come from a pruned pool, not a stale cache

When a Debian release reaches end-of-life, `deb.debian.org` can keep serving its frozen `dists/<codename>-security` index (with a recent, validly-signed InRelease) while the mirror-backed `pool/` has already had the package files removed — so `apt-get update` succeeds, and then `apt-get install` 404s on the exact versions the live index advertises. This looks like a stale apt-list cache but is not: clearing the BuildKit `--mount=type=cache` apt mounts, or rebuilding with `--no-cache`, will not fix it, because the freshly-downloaded index still points at files the mirrors no longer carry. Diagnose it by (1) confirming the advertised file is really gone with a ranged GET on the `Filename:` value from the Packages index (`curl -s -o /dev/null -w '%{http_code}' -r 0-99 <url>` — prefer a ranged GET over `-I`, HEAD is unreliable on some mirrors), (2) comparing hosts, since `deb.debian.org` is mirror-backed while `security.debian.org` is the origin and may still hold a file the mirrors have dropped, and (3) checking `archive.debian.org`, where EOL releases move — though `<codename>-security` is often absent there. The durable fix is to migrate the base image to a supported release, not to pin packages or retarget sources: Debian 11 bullseye LTS ended 2026-08-31, Debian 12 bookworm LTS runs to 2028-06-30, Debian 13 trixie to 2030-06-30. For the official PHP images the swap is a one-line `FROM` change (`php:<ver>-fpm-<codename>`), and `install-php-extensions` handles trixie from v2.11.12 onward.
