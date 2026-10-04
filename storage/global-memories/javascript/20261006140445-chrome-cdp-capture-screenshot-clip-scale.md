---
date: 2026-10-06
keywords: ["chrome", "cdp", "screenshot"]
trigger-on: ["chrome-headless-cdp", "cdp-capture-screenshot"]
---

## Headless Chrome CDP: captureScreenshot needs clip.scale, and a wide viewport for horizontal layouts

Driving Chrome over the DevTools Protocol (Node's built-in `WebSocket` + `fetch`, no puppeteer) to
screenshot one element:

- `Page.captureScreenshot` with a `clip` **requires** `clip.scale` — omitting it fails with
  "Failed to deserialize params.clip.scale - mandatory field missing" and returns no data. Pass
  `scale: 1` (or 2) explicitly.
- The headless default viewport is narrow (~800px), so a responsive page **stacks columns that should
  sit side by side**. Call `Emulation.setDeviceMetricsOverride` with a wide `width` (e.g. 1920) before
  measuring/capturing so the layout goes horizontal; measure the element with
  `getBoundingClientRect()` + `scrollWidth/scrollHeight`.
- A collapsed accordion hides content: expand it in-page first (e.g. add the app's `expanded` class to
  every `h2`), or the screenshot shows headers only.
- Launch with `--window-size=W,H`; make the viewport at least as tall as the content to avoid capture
  tiling/seams.
- An SVG using `<foreignObject>` (HTML) paints only in browsers; to make an exported SVG paint in ANY
  viewer, embed the element's PNG screenshot instead: `<image xlink:href="data:image/png;base64,…"/>`.
