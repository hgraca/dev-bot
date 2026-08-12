---
layout: page
title: Tools
description: Every tool DevBot installs and manages — all local, all automatic.
nav_section: docs
---

## Memory &amp; Session

| Tool                                       | Description                                                 |
| ------------------------------------------ | ----------------------------------------------------------- |
| [Session Capture](/tools/remember-session) | Auto-promotes learnings to memory after commits and wrap-up |

## Codebase Understanding

| Tool                                    | Description                                            |
| --------------------------------------- | ------------------------------------------------------ |
| [Graphify](/tools/graphify)             | Auto-built structural knowledge graph of the codebase  |
| [Codebase Index](/tools/codebase-index) | Find code by natural language description              |
| [Repomix](/tools/repomix)               | Packs many files into a single compressed context dump |

## Knowledge Vault

| Tool              | Description                              |
| ----------------- | ---------------------------------------- |
| [QMD](/tools/qmd) | Semantic search over the knowledge vault |

## Safety &amp; Reliability

| Tool                                              | Description                                         |
| ------------------------------------------------- | --------------------------------------------------- |
| [Guards](/tools/guards)                           | Prevent dangerous commands from being executed      |
| [Auto-Recover](/tools/auto-recover)               | Automatic recovery from transient provider errors   |
| [Agent Communication](/tools/agent-communication) | Structured inter-agent protocol with status markers |

## Formatting

| Tool                              | Description                        |
| --------------------------------- | ---------------------------------- |
| [Format MD](/tools/format-md)     | Markdown formatting via prettier   |
| [Format JSON](/tools/format-json) | JSON/JSONC formatting via prettier |
| [Format YML](/tools/format-yml)   | YAML formatting via prettier       |

## Infrastructure

| Tool                      | Description                              |
| ------------------------- | ---------------------------------------- |
| [Ollama](/tools/ollama)   | Local LLM inference server (port 18434)  |
| [LiteLLM](/tools/litellm) | Unified API proxy for 100+ LLM providers |

## Observability &amp; DevOps

| Tool                            | Description                        |
| ------------------------------- | ---------------------------------- |
| [Git Report](/tools/git-report) | Git state snapshot tool            |
| [Tree](/tools/tree)             | Directory tree inspection          |
| [K8s Lint](/tools/k8s)          | Kubernetes manifest linting        |
| [SigNoz](/tools/signoz)         | Observability platform integration |

## MCP Integrations

MCP servers shipped as standalone integrations (no dedicated tool page):

| MCP Server          | Purpose                                                  |
| ------------------- | -------------------------------------------------------- |
| **Chrome DevTools** | Browser inspection and debugging                         |
| **Playwright**      | Browser automation and testing                           |
| **Context7**        | Library and framework documentation lookup               |
| **Exa (websearch)** | Web search                                               |
| **JetBrains**       | IDE integration — inspections, debugging, database tools |
| **Next DevTools**   | Next.js runtime diagnostics (react module)               |
| **Svelte**          | Svelte framework integration (svelte module)             |
| **devbot-tools**    | Exposes DevBot tool scripts as MCP tools                 |

Graphify, Codebase Index, QMD, and SigNoz also expose MCP servers — see their tool sections above. The `aws` module ships an `aws-mcp` server but is disabled by default.

## Conventions (Skills)

These modules provide agent-readable skill instructions for specific technologies and workflows:

| Module               | Coverage                                                                |
| -------------------- | ----------------------------------------------------------------------- |
| **dev**              | PHP, Laravel, PHPUnit, Message Bus (CQRS), REST APIs, Git, Makefile     |
| **architecture**     | DDD + Hexagonal + CQRS layers, ADRs, codebase audits                    |
| **docker**           | Dockerfile authoring patterns                                           |
| **react**            | React 18+ and Next.js conventions                                       |
| **svelte**           | Svelte development conventions                                          |
| **security**         | PHP security review, threat modelling, secure code review               |
| **git**              | Conventional/atomic/fixup commits, history surgery                      |
| **memory**           | Vault management, memory search, session capture                        |
| **explore**          | Code search, context gathering, codebase reports                        |
| **devteam**          | Multi-agent planning, implementation, and review workflows              |
| **docs**             | Architecture diagrams and use-case maps                                 |
| **self-improvement** | Meta-optimization: skill creation, retrospectives, planning improvement |

## Plugins

Plugins are OpenCode extensions that run automatically on lifecycle events — guards, auto-recover, format-md/json/yml, remember-session, graphify, k8s lint, memory reindex, and agent communication. See [Plugins](/tools/plugins) for the complete list and event reference.
