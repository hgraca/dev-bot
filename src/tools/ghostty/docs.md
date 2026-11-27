---
title: "Ghostty"
description: "GPU-accelerated terminal emulator, installed for Linux and macOS."
---

[Ghostty](https://ghostty.org) is a fast, native, GPU-accelerated terminal emulator.

## What this module installs

| Platform                 | Route                                                                                                                                                                           |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| macOS                    | `brew install --cask ghostty` (the official, notarized `.dmg`, repackaged); an app installed from the `.dmg` counts as installed and is only flagged as unmanaged               |
| Ubuntu (and derivatives) | `apt-get install ghostty` when the archive carries it (26.04+); otherwise the community PPA, `ppa:mkasberg/ghostty-ubuntu`, removed again if the install it was added for fails |
| Debian                   | refused — no ghostty package, and the community PPA publishes Ubuntu suites only — with a pointer to the project's `.deb` releases                                              |
| other Linux              | told to install it by hand (`https://ghostty.org/docs/install/binary`)                                                                                                          |

An installed ghostty is left alone. Debian gets a clear refusal — no ghostty package, and the community PPA publishes Ubuntu suites only — pointing at the project's `.deb` releases; any other Linux is told to install it by hand. A machine without Homebrew, `add-apt-repository` or a usable `sudo` is told what to run instead of being half-installed.

## Making it the default terminal

The module never changes the default itself — it prints the command after `devbot install` and after `devbot update`:

- **Linux**: `sudo update-alternatives --set x-terminal-emulator $(command -v ghostty)` — the alternative desktop launchers and `Ctrl+Alt+T` resolve.
- **macOS**: there is no system default-terminal switch (`ghostty +list-actions` carries none), so the hint points at launching it: `open -a Ghostty`, or from Applications.

## Update behaviour

`devbot update` upgrades an installed ghostty — `brew upgrade --cask` on macOS, `apt-get install --only-upgrade` on the Ubuntu family — and reprints the hint. A distribution with no devbot-managed upgrade path is told to update it by hand. Because `devbot update --auto` can run unattended at session start, the update path uses `sudo -n` and skips with a warning rather than waiting for a password.

## Enablement

**Disabled by default**: opt in with `"modules": { "ghostty": true }` in `.devbot.global.jsonc` (the global map is the switch — install provisions the machine), then run `devbot install`. A disabled module installs nothing and prints nothing. The `1.25.0` migration writes the explicit `false` for a config that names neither module, and never overrides a value the machine set itself.
