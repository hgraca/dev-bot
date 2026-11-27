---
date: 2026-11-27
keywords: ["docker", "base-image", "build-cache", "buildkit"]
aliases: ["cache miss on FROM", "why did the build take 40 minutes"]
---

## A republished base image rebuilds every layer above it

A Dockerfile whose `FROM php:8.5.13-fpm-bookworm` names a *tag* is rebuilt from that line down whenever the tag points at a new digest — a republished base (security rebuild, same version, new digest) invalidates every cached layer above it, including a 40-minute extension compile. The symptom looks like a broken cache: same instruction, same Dockerfile, yet `RUN install-php-extensions …` executes instead of printing `CACHED`. Compare the resolved `FROM …@sha256:…` in two build logs before blaming the cache: two different digests mean the rebuild was unavoidable. Pinning the digest (`FROM image@sha256:…`) makes the change deliberate; a separate base image carrying the compiled extensions moves the cost off the critical path.
