---
date: 2026-05-20
keywords: ["docker", "ollama", "models", "pull"]
---

## Ollama does not auto-download models on first request

When a request arrives for a model that is not present locally, Ollama returns an error (model not found) — it does not trigger an automatic download. Users must explicitly pull the model before use: `docker exec devbot-ollama ollama pull <model-name>`. This applies whether Ollama is accessed directly or through a proxy like LiteLLM. Document this as a prerequisite whenever instructing users to configure an Ollama model.
