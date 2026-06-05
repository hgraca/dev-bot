---
date: 2026-04-16
keywords: ["obsidian"]
---

## M-FLOW-065: Human-in-the-loop for GUI app setup

Obsidian requires manual plugin installation and API key retrieval. Fully automated setup is impossible for GUI applications that require user interaction.
For GUI applications, design scripts that pause and provide clear step-by-step instructions to the user. Collect required information (API keys, settings) via terminal input after the user completes manual steps. Validate input and provide fallback options.
