# Spec: Ganzfeld Flicker App (macOS, Swift + Metal)

**Goal:** A borderless, fullscreen Metal app that renders a square-wave red flicker at a user-controlled frequency and brightness.

**Tech stack:** Swift, Metal (MTKView), no third-party dependencies.

**Display:**
- Fullscreen, borderless, no menu bar, no window frame, cursor hidden.
- Render at the display's native refresh rate (use `CADisplayLink` or `MTKView.preferredFramesPerSecond = 0`).

**Rendering:**
- Full-screen quad with a fragment shader.
- The shader outputs either `(r, 0, 0)` or `(0, 0, 0)` based on a square-wave clock.
- `r` is a uniform float in range **100–255** (integer), default **150**.
- Square wave period is `1.0 / frequency` seconds. At the "on" phase, output red. At the "off" phase, output black.
- Phase is computed from `time * frequency`, so changing frequency does not cause a phase jump (use a phase accumulator: `phase += deltaTime * frequency`).

**Controls:**

| Input | Effect |
|---|---|
| Mouse move **up** (negative Δy) | Increase `r` by 1 per pixel moved (clamp to 255) |
| Mouse move **down** (positive Δy) | Decrease `r` by 1 per pixel moved (clamp to 100) |
| Mouse move **left** (negative Δx) | Decrease `frequency` by 0.1 Hz per pixel moved (clamp to 1.0) |
| Mouse move **right** (positive Δx) | Increase `frequency` by 0.1 Hz per pixel moved (clamp to 50.0) |
| Mouse **click** (left button) | Toggle animation on/off |
| **ESC** | Quit the app |

**Animation state:**
- `isRunning: Bool`, default **true**.
- When **off**: render solid black regardless of frequency/brightness.
- When **on**: render the square wave.
- Toggling does not reset the phase accumulator.

**Status bar:**
- Bottom of screen, full width, height ~20 px, semi-transparent black background (`rgba(0,0,0,0.6)`).
- Text: left-aligned, 8 pt, white, monospaced.
- Content: `"freq: {frequency:.1f} Hz   red: {r}"`
- Update every frame (or on change).

**Defaults at launch:**
- `r = 150`
- `frequency = 7.5 Hz`
- `isRunning = true`

**Structure (suggested):**
- `AppDelegate` / `@main` entry
- `FlickerView: NSView, MTKViewDelegate` — owns the Metal pipeline, render loop, and status bar drawing
- `FlickerView` handles all mouse events (`mouseMoved`, `mouseDragged`, `mouseDown`, `keyDown`)
- Fragment shader (MSL): takes `float r` and `float phase` as uniforms, outputs `float4(fract(phase) < 0.5 ? float3(r/255.0, 0, 0) : float3(0), 1.0)`

**Edge cases:**
- If `isRunning == false`, ignore the phase and always output black.
- Clamp all values on every input event.
- The status bar should remain visible even when animation is off.   