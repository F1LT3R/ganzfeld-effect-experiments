# 🎞️ GanzFlicker — Ganzfeld Flicker Simulator

A fullscreen red/black flicker generator for exploring the [**Ganzfeld effect**](https://en.wikipedia.org/wiki/Ganzfeld_effect) and perceptual flicker responses. Drag your mouse to tune the flash frequency (1–50 Hz) and modulation depth (100–255) in real time — no buttons, no forms, just flicker.

# ⚠️🚨👩🏼‍🔬 SAFETY FIRST – Rapid full-screen flashes can trigger **photosensitive epilepsy** and discomfort. If anything feels wrong, press `ESC` or close the tab. Do not stare at high frequencies for long!
# 🗽⚖️👨🏾‍⚖ THE CREATOR OF THIS CODE ACCEPTS NO LIABILITY FOR HARM. THIS CODE IS SHARED FOR MEDICAL RESEARCH USE ONLY! _USE AT YOUR OWN RISK_ !!!
# ⚠️ TODAY IS NOT A GOOD DAY TO DIE. ALWAYS CONSULT A MEDICAL PROFESSIONAL _BEFORE_ RUNNING THIS CODE !!! ⚠️

You can learn more about the Ganzfeld Effect here: [https://www.youtube.com/watch?v=hnEGPjrRGGo](https://www.youtube.com/watch?v=hnEGPjrRGGo)

## 🚀 Quick Start

**WebGL version (recommended)** — just open it, no server needed (works from `file://`):

```bash
open index-webgl.html
```

**CSS version** — needs to be served over `http` and initializes on your first keypress or click (browser autoplay policy):

```bash
python3 -m http.server 8000
# → http://localhost:8000  (then press any key or click once)
```

## 🎮 Controls

| Input | Effect |
|---|---|
| 🖱️ Drag ← → | Frequency: 1–50 Hz |
| 🖱️ Drag ↑ ↓ | Modulation depth: 0–255 |
| ␣ Space | Pause / resume |
| ⎋ Esc | Stop & clean up |

A circle indicator follows the cursor while dragging, showing the live `Hz` / depth values. The top-left overlay always shows the current settings.

## 📦 Versions

| | 🎨 CSS (`index.html`) | 🌐 WebGL (`index-webgl.html`) |
|---|---|---|
| **Rendering** | `requestAnimationFrame` rewriting a div's `background-color` | Fullscreen WebGL triangle — one uniform, one 3-vertex draw call per frame |
| **Timing** | `AudioContext.currentTime` (high-res audio clock) | `requestAnimationFrame` timestamp (display vsync instant) |
| **Starts** | On first keypress / click (autoplay policy) | Immediately on load |
| **`file://`** | ❌ needs `http` | ✅ works |
| **Flip precision** | Phase sampled from the audio clock each frame | Phase computed at the vsync instant — every flip lands exactly on a frame boundary |

**Why WebGL feels smoother:** the color is written straight to the GPU framebuffer (no DOM style invalidation or CSS paint step), and the phase is derived from the display's vsync timestamp, so red/black flips are locked to frame boundaries with no drift.

**Why the CSS version needs a click:** an `AudioContext` created without a prior user gesture is born *suspended*, and a suspended context's clock never advances — freezing the flicker phase. `ganzfeld-flicker.js` therefore waits for your first `keydown`/`mousedown` before creating the context.

## 📁 Layout

```
├── index.html                 # CSS version entry point
├── ganzfeld-flicker.js        # CSS version (rAF + background-color, AudioContext timing)
├── index-webgl.html           # WebGL version entry point
├── ganzfeld-flicker-webgl.js  # WebGL version (fullscreen triangle, vsync timing)
├── backups/                   # historical versions (gansflicker.js, v2, v3, sim.cjs, …) — gitignored
└── .pi/                       # session backups — gitignored
```

## 🧪 Under Test

Ongoing question: **is the WebGL flicker smoother than the CSS flicker?** Both are ultimately quantized to the display refresh rate, so at frequencies that alias the refresh (e.g. 30 or 40 Hz on a 60 Hz display) you'll see beating in both — that's sampling physics, not jank. The test is whether the WebGL version's frame-boundary-locked flips eliminate the last visible stutter.

## 🛠️ Notes

- Both versions are single-file IIFEs with zero dependencies — paste the `.js` into any page's console and it works.
- Canvas resolution is capped at 2× DPR (a solid color needs no retina resolution).
- The WebGL version degrades gracefully: if WebGL is unavailable it tells you in the overlay.
