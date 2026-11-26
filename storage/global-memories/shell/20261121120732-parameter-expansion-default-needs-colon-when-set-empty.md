---
date: 2026-11-21
keywords: ["shell", "parameter-expansion", "default-value", "launcher", "empty-variable"]
---

## A default value must use `:-` when a launcher forwards the variable set-but-empty

`${VAR-word}` substitutes only when `VAR` is **unset**; `${VAR:-word}` substitutes when it is unset **or empty**. They are both valid POSIX, so the short form reads like a typo — and it silently does nothing in the shape most wrappers produce. A launcher that exports every knob for the child (`-e "MODEL=${MODEL:-}"` into a container, `env MODEL="$MODEL" cmd`, a sourced env file with `MODEL=`) leaves the variable **set and empty**, so `${VAR-word}` yields the empty string and the intended default never applies. Symptom: the documented default never takes effect in the wrapped path while a direct run behaves correctly. Use `:-` whenever the value can arrive empty; reserve `${VAR-word}` for "unset means do not set it at all", and test it through the real launcher rather than by running the script by hand.
