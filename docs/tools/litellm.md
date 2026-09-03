---
layout: page
title: LiteLLM
description: Unified API proxy for 100+ LLM providers.
nav_section: docs
---

Proxy that provides unified API access to multiple model providers. Optional — disabled by default.

## Configuration

Enable by removing from `disabled_modules` in `.devbot.global.jsonc`. Depends on Ollama service health.

`install.sh` copies the working config (`config.yaml`) to a `litellm.config.yaml` at the dev-bot root; edit that copy (not the module template) to tune providers, keys, and routing.

Configuration templates shipped with the module (under `src/tools/litellm/`):

| File                    | Purpose                                                               |
| ----------------------- | --------------------------------------------------------------------- |
| `config.yaml`           | Working free-tier config — copied to `litellm.config.yaml` at install |
| `config.free.dist.yaml` | Free-tier distribution template (model-routing skeleton)              |
| `config.paid.dist.yaml` | Paid-tier distribution template                                       |

A reference copy of the free-tier working config is kept at [examples/litellm.config.free.yaml](/examples/litellm.config.free.yaml).

## See also

- [Ollama](/tools/ollama) — local LLM inference
