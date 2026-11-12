---
date: 2026-11-12
keywords: ["dialog", "css", "lightbox", "centering", "html"]
---

# A constrained <dialog> is not centred until you set inset and margin

A `<dialog>` opened with `showModal()` is centred by the UA stylesheet, but constraining it to the viewport (`max-width: 96vw; max-height: 96vh; padding: 0; border: none`) made it render flush left in Chrome — the constrained content box no longer satisfies the UA's centring rules.

State the centring explicitly:

```css
.lightbox {
  position: fixed;
  inset: 0;
  margin: auto;
  max-width: 96vw;
  max-height: 96vh;
}
```

Backdrop clicks close it for free: a click on `::backdrop` targets the dialog element itself, so `if (event.target === dialog) dialog.close()` works without extra markup.

Verified with a same-origin iframe harness that clicks the trigger, then `dialog.click()`, then asserts `dialog.open` — open, backdrop-close and reopen all confirmed, and the capture showed the image centred.
