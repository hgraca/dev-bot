---
date: 2026-05-20
keywords: ["docker", "ollama", "model", "pull"]
---

## Ollama does not auto-download models on request

When a request arrives for a model that is not present locally, Ollama returns an error (model not found) — it does not download the model automatically. Users must explicitly pull the model before use: `docker exec devbot-ollama ollama pull <model-name>`. This applies whether requests come directly to Ollama or via a proxy like LiteLLM. Document this prominently in any user-facing guide that references Ollama model names.
