---
date: 2026-08-10
keywords: ["gemma3", "ollama", "vision", "describe-image"]
---

# gemma3:4b Vision Model Gotchas with Ollama

gemma3:4b in Ollama supports vision (`/api/show` reports `"capabilities": ["completion", "vision"]`) but has critical gotchas:

1. **Vision processing is unusably slow on CPU** (~100 seconds for image encode alone on a 2847×1028 PNG). GPU is mandatory.
2. **Even with GPU, vision requests crash with HTTP 500** after ~90 seconds unless `num_predict` is capped. The model exhausts its 4096-token context window during long generations and the llama-server cancels the task. Cap at 300 tokens.
3. **Vision encoder may not offload to GPU** even when text layers are on CUDA. Prompt processing showed 3.67 tok/s for vision tokens vs much faster for text-only. Image downsizing helps compensate.
4. **Always resize images before sending** — use Pillow to scale to max 512px on the longest side and convert to JPEG (quality 85). This reduces base64 payload from ~549K to ~24K and drastically cuts vision encode time.
5. **Keep the model warm** — Ollama unloads after idle. First request after idle includes model load time (~1s with GPU, much longer on CPU).
