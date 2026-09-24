---
date: 2026-09-24
keywords: ["chrome-headless", "screenshot", "design-review", "visual-verification"]
---

# A full-page headless screenshot tiles when the window is shorter than the page — and reads as a layout bug

`google-chrome --headless=new --screenshot=<out.png> --window-size=W,H <url>` captures the whole page, but when the page is taller than `H` the capture is stitched from tiles. The seams are not obvious in the image: content below a seam renders shifted horizontally, so paragraphs and tables following a `<pre>` block appear to escape the centred content column and run to the left edge.

A vision model reported exactly that as a real defect on a page where every element measured inside the container: `container` left 140 / right 1260, `.prose` left 164 / right 944, `document.documentElement.scrollWidth == window.innerWidth` at 1400px, and a balanced DOM (14/14 `<div>`, 1/1 `<pre>`, 22/22 `<code>`). The layout was fine; the capture was not.

Fix: size the window to the whole page — roughly 5200px tall for a desktop docs page and 8000px for a mobile one in this repo — or judge structure from the DOM instead of the image. When a delegated visual review reports a structural break, confirm it with `getBoundingClientRect()` / `scrollWidth` before changing CSS.
