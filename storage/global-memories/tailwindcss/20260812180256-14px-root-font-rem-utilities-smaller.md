---
date: 2026-08-12
keywords: ['tailwindcss', 'root-font-size', 'rem', 'shadcn']
trigger-on: ['tailwind-14px-root-font', 'rem-utilities-smaller-than-expected']
---

## A 14px root font makes rem-based Tailwind utilities resolve smaller than shadcn assumes

shadcn/Tailwind components are authored against a 16px root font, so when a dashboard sets `html`/`body` to `font-size: 14px`, every rem-based utility shrinks: `px-2` becomes 7px (not 8px), `py-0.5` becomes 1.75px (not 2px), `leading-4` becomes 14px (not 16px), `size-3` becomes 10.5px (not 12px), `h-9` becomes 31.5px (not 36px). This causes subtle 1–2px mismatches when matching hand-rolled px values. Fix: when fidelity to a specific pixel value matters, use explicit arbitrary values (`px-[8px]`, `py-[3px]`, `leading-[16px]`, `text-[11.5px]`, `h-[52px]`) instead of rem scale classes. The badge atom base was aligned to the dashboard `.badge` using `px-[8px] py-[3px] text-[11.5px]` for this reason.
