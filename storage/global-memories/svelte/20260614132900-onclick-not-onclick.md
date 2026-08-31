---
date: 2026-06-14
keywords: ["svelte", "svelte5", "onclick"]
---

## Use onclick not on:click in Svelte 5

Svelte 5 replaced `on:click` with `onclick` as a plain attribute. The `on:click` directive is Svelte 4 syntax. In Svelte 5, write `<button onclick={() => handler()}>` not `<button on:click={() => handler()}>`. Same for all other events: `on:submit` → `onsubmit`, `on:input` → `oninput`, etc. The `svelte5-best-practices` and `svelte-runes` skills both enforce this.
