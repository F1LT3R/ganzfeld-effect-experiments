# GanzFlicker — Swift + Metal (macOS)

Borderless, fullscreen Metal app that renders a square-wave red flicker, per [SPEC.md](./SPEC.md).

## ⚠️ Safety

Full-screen flashes can trigger **photosensitive epilepsy**. Do not stare at high frequencies for long. **ESC quits** — the app has no menu bar or window frame.

## Run

```bash
cd swift-metal
swift run                     # debug build & run
# or
swift build -c release
.build/release/GanzFlicker
```

No third-party dependencies — Swift + system Metal toolchain only.

## Controls

| Input | Effect |
|---|---|
| Mouse **up** (1 per pixel) | Increase red: 100 → 255 |
| Mouse **down** (1 per pixel) | Decrease red: 255 → 100 |
| Mouse **left** (0.1 Hz per pixel) | Decrease frequency: 50 → 1 Hz |
| Mouse **right** (0.1 Hz per pixel) | Increase frequency: 1 → 50 Hz |
| Mouse **click** | Toggle animation on/off (phase accumulator preserved) |
| **ESC** | Quit |

Defaults at launch: `red = 150`, `frequency = 7.5 Hz`, animation running.

## Implementation notes

- `FlickerView` subclasses `MTKView` (an `NSView`) and serves as its own `MTKViewDelegate` — it owns the pipeline, the render loop, and the status bar, and handles `mouseMoved`/`mouseDragged`/`mouseDown`/`keyDown` directly.
- The window is borderless, covers `NSScreen.main.frame`, sits above the menu-bar level, and the app sets `NSApp.presentationOptions = [.hideMenuBar, .hideDock]` plus `NSCursor.hide()`.
- `preferredFramesPerSecond = 0` → the render loop runs at the display's native refresh rate (including ProMotion).
- The square wave is a fullscreen triangle + fragment shader; `r` (100–255) and the fractional phase are uniform floats, matching the spec's `fract(phase) < 0.5 ? red : black`.
- The phase is a `Double` accumulator (`phase += dt * frequency`), so changing frequency never causes a phase jump. The fractional part is passed to the shader as `Float`, which avoids float32 precision drift over long sessions.
- When the animation is off the shader always outputs solid black; the status bar stays visible.
- Status bar: 20 pt tall, full width, `rgba(0,0,0,0.6)`, 8 pt white monospaced, left-aligned `"freq: {x} Hz   red: {r}"`, updated on change.
- Dev: `GF_SMOKE_TEST=1 .build/release/GanzFlicker` compiles the shader and pipeline headless and exits without taking over the screen.
