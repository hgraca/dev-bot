#!/usr/bin/env node
// =============================================================================
// src/agentic/docs/tools/ImpactDiagram/render-app-svg.mjs
// Render ImpactDiagram.html with a JSON payload in headless Chrome (CDP), then
// embed a screenshot of its #app element inside a plain SVG <image>. This keeps
// the browser's full rendering while producing an SVG that paints in ANY viewer
// (no foreignObject, which non-browser viewers drop). Node's built-in WebSocket
// + fetch drive CDP — no npm dependencies.
//
// Usage: render-app-svg.mjs --html <ImpactDiagram.html> --json <map.json> --out <out.svg>
// =============================================================================

import { spawn } from "node:child_process"
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`)
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback
}

const htmlPath = resolve(arg("html", ""))
const jsonPath = resolve(arg("json", ""))
const outPath = resolve(arg("out", ""))
const scale = Number(arg("scale", "2"))
if (!htmlPath || !jsonPath || !outPath) {
  console.error("FATAL: usage: render-app-svg.mjs --html <html> --json <json> --out <svg>")
  process.exit(1)
}

const port = Number(arg("port", String(9300 + Math.floor(Math.random() * 500))))
const profile = mkdtempSync(join(tmpdir(), "impact-cdp-"))
const data = Buffer.from(readFileSync(jsonPath)).toString("base64")
const pageUrl = `file://${htmlPath}?data=${encodeURIComponent(data)}`

const sleep = (ms) => new Promise((resolveImpl) => setTimeout(resolveImpl, ms))

const chrome = spawn(
  "google-chrome",
  [
    "--headless=new",
    "--no-sandbox",
    "--disable-gpu",
    "--hide-scrollbars",
    "--window-size=1920,1080",
    `--remote-debugging-port=${port}`,
    `--user-data-dir=${profile}`,
    "about:blank",
  ],
  { stdio: "ignore" },
)

function cleanup(code) {
  try {
    chrome.kill()
  } catch {}
  try {
    rmSync(profile, { recursive: true, force: true })
  } catch {}
  process.exit(code)
}

async function waitForChrome() {
  for (let i = 0; i < 60; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}/json/version`)
      if (res.ok) return
    } catch {}
    await sleep(100)
  }
  throw new Error("headless Chrome did not start")
}

async function newTarget(url) {
  const res = await fetch(`http://127.0.0.1:${port}/json/new?${url}`, { method: "PUT" })
  if (!res.ok) throw new Error(`/json/new returned HTTP ${res.status}`)
  return res.json()
}

/** The #app box, in page coordinates. */
const RECT_EXPR = `(() => {
  const a = document.getElementById('app');
  if (!a) return { error: 'no #app element' };
  a.style.display = 'block';
  const r = a.getBoundingClientRect();
  return {
    x: Math.round(r.left + window.scrollX),
    y: Math.round(r.top + window.scrollY),
    w: Math.max(1, Math.ceil(a.scrollWidth || r.width)),
    h: Math.max(1, Math.ceil(a.scrollHeight || r.height)),
  };
})()`

async function main() {
  await waitForChrome()
  const target = await newTarget(pageUrl)
  const ws = new WebSocket(target.webSocketDebuggerUrl)
  await new Promise((res, rej) => {
    ws.onopen = res
    ws.onerror = rej
  })

  let id = 0
  const pending = new Map()
  ws.onmessage = (event) => {
    const msg = JSON.parse(event.data)
    if (msg.id && pending.has(msg.id)) {
      pending.get(msg.id)(msg)
      pending.delete(msg.id)
    }
  }
  const send = (method, params = {}) =>
    new Promise((res) => {
      const mid = ++id
      pending.set(mid, res)
      ws.send(JSON.stringify({ id: mid, method, params }))
    })

  await send("Page.enable")
  // A wide viewport so the app lays the layer columns out horizontally; a narrow
  // one makes its responsive CSS stack them into a single column. Tall enough
  // that the whole #app fits without beyond-viewport capture.
  await send("Emulation.setDeviceMetricsOverride", {
    width: 1920,
    height: 6000,
    deviceScaleFactor: 1,
    mobile: false,
  })
  for (let i = 0; i < 60; i++) {
    const ready = await send("Runtime.evaluate", {
      expression: "document.readyState === 'complete' && !!document.querySelector('#app *')",
      returnByValue: true,
    })
    if (ready.result?.result?.value === true) break
    await sleep(100)
  }
  await sleep(300)

  // Sections render collapsed until their h2 is expanded — open them all so the
  // captured render shows the information, not just the headers.
  await send("Runtime.evaluate", {
    expression:
      "document.querySelectorAll('#app h2').forEach(function (h) { h.classList.add('expanded'); })",
    returnByValue: true,
  })
  await sleep(200)

  const measured = await send("Runtime.evaluate", { expression: RECT_EXPR, returnByValue: true })
  const rect = measured.result?.result?.value
  if (!rect || rect.error) throw new Error(rect?.error || "could not measure #app")

  const shot = await send("Page.captureScreenshot", {
    format: "png",
    clip: { x: rect.x, y: rect.y, width: rect.w, height: rect.h, scale },
  })
  const png = shot.result?.data
  if (!png) {
    console.error(`captureScreenshot: ${JSON.stringify(shot).slice(0, 400)}`)
    throw new Error("screenshot returned no data")
  }

  const svg =
    `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" ` +
    `width="${rect.w}" height="${rect.h}" viewBox="0 0 ${rect.w} ${rect.h}">` +
    `<image x="0" y="0" width="${rect.w}" height="${rect.h}" ` +
    `xlink:href="data:image/png;base64,${png}"/></svg>\n`
  writeFileSync(outPath, svg)
  console.error(`Wrote app SVG: ${outPath} (${rect.w}x${rect.h} @${scale}x)`)
  ws.close()
}

main().then(
  () => cleanup(0),
  (error) => {
    console.error(`FATAL: ${error.message}`)
    cleanup(1)
  },
)
