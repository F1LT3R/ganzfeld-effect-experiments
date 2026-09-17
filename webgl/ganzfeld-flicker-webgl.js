// Ganzflicker Generator — WebGL Version (v4)
//
// Replacement for the CSS background-color flicker in ganzflicker3.js:
// a full-screen WebGL triangle, one uniform, one draw call per frame.
//
// Controls (same as v3):
//   drag left/right : frequency (1-40 Hz)
//   drag up/down    : modulation depth (0-255)
//   space           : pause / resume
//   esc             : stop
//
// Why this should be smoother than the CSS version:
//   * The phase is computed from the requestAnimationFrame timestamp —
//     the display's vsync instant — so each red/black flip lands exactly
//     on a frame boundary, with no drift and no DOM style invalidation.
//   * The color is written straight to the GPU framebuffer; there is no
//     CSS paint step to schedule or coalesce.
//   * No AudioContext: no autoplay policy, starts on load, and works
//     from file:// as well as http.

(function () {
  'use strict';

  // ---------- scaffolding (same look as v3) ----------

  const overlay = document.createElement('div');
  overlay.id = 'ganzflicker-overlay';
  overlay.style.position = 'fixed';
  overlay.style.top = '0';
  overlay.style.left = '0';
  overlay.style.width = '100vw';
  overlay.style.height = '100vh';
  overlay.style.zIndex = '999998';
  overlay.style.pointerEvents = 'none';
  overlay.style.fontFamily = 'monospace';
  overlay.style.fontSize = '14px';
  overlay.style.color = 'rgba(255, 255, 255, 0.7)';
  overlay.style.padding = '20px';
  overlay.style.boxSizing = 'border-box';
  document.body.appendChild(overlay);

  const canvas = document.createElement('canvas');
  canvas.id = 'ganzflicker-canvas';
  canvas.style.position = 'fixed';
  canvas.style.top = '0';
  canvas.style.left = '0';
  canvas.style.width = '100vw';
  canvas.style.height = '100vh';
  canvas.style.display = 'block';
  canvas.style.zIndex = '999997';
  document.body.appendChild(canvas);

  const circle = document.createElement('div');
  circle.id = 'ganzflicker-circle';
  circle.style.position = 'fixed';
  circle.style.width = '80px';
  circle.style.height = '80px';
  circle.style.borderRadius = '50%';
  circle.style.backgroundColor = 'rgba(255, 255, 255, 0.8)';
  circle.style.zIndex = '999999';
  circle.style.pointerEvents = 'none';
  circle.style.transform = 'translate(-50%, -50%)';
  circle.style.display = 'none'; // v3 clobbered this to flex by accident
  circle.style.flexDirection = 'column';
  circle.style.justifyContent = 'center';
  circle.style.alignItems = 'center';
  circle.style.fontSize = '12px';
  circle.style.fontWeight = 'bold';
  circle.style.color = 'rgb(0, 0, 0)';
  circle.style.fontFamily = 'monospace';
  circle.style.lineHeight = '1.2';
  document.body.appendChild(circle);

  // ---------- WebGL ----------

  const gl = canvas.getContext('webgl', {
    antialias: false,
    alpha: false,
    depth: false,
    stencil: false,
    powerPreference: 'high-performance',
  });

  if (!gl) {
    overlay.textContent =
      'WebGL is not available in this browser — use the CSS version instead.';
    circle.remove();
    canvas.remove();
    return;
  }

  function compile(type, src) {
    const s = gl.createShader(type);
    gl.shaderSource(s, src);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
      throw new Error('shader compile: ' + gl.getShaderInfoLog(s));
    }
    return s;
  }

  const program = gl.createProgram();
  gl.attachShader(
    program,
    compile(
      gl.VERTEX_SHADER,
      'attribute vec2 aPos;' +
        'void main() { gl_Position = vec4(aPos, 0.0, 1.0); }'
    )
  );
  gl.attachShader(
    program,
    compile(
      gl.FRAGMENT_SHADER,
      'precision mediump float;' +
        'uniform vec3 uColor;' +
        'void main() { gl_FragColor = vec4(uColor, 1.0); }'
    )
  );
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    throw new Error('link: ' + gl.getProgramInfoLog(program));
  }
  gl.useProgram(program);

  // One giant triangle covering the viewport: the cheapest possible
  // fullscreen primitive (3 vertices, no clear pass, no texture).
  const buf = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buf);
  gl.bufferData(
    gl.ARRAY_BUFFER,
    new Float32Array([-1, -1, 3, -1, -1, 3]),
    gl.STATIC_DRAW
  );
  const aPos = gl.getAttribLocation(program, 'aPos');
  gl.enableVertexAttribArray(aPos);
  gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0);
  const uColor = gl.getUniformLocation(program, 'uColor');

  function resize() {
    // Cap DPR at 2: a solid color needs no retina resolution.
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.max(1, Math.floor(window.innerWidth * dpr));
    canvas.height = Math.max(1, Math.floor(window.innerHeight * dpr));
    gl.viewport(0, 0, canvas.width, canvas.height);
  }
  window.addEventListener('resize', resize);
  resize();

  // ---------- state ----------

  let frequency = 10; // Hz
  let modulationDepth = 255; // 0-255
  let isMouseDown = false;
  let startX = 0;
  let startY = 0;
  let startFrequency = 7.5;
  let startModulation = 255;
  let mouseX = 0;
  let mouseY = 0;
  let isAnimating = true;
  let rafId = 0;
  let t0 = -1; // rAF timestamp of (re)start; <0 = init on next frame
  let stopped = false;

  // ---------- mouse ----------

  document.addEventListener('mousedown', (e) => {
    isMouseDown = true;
    startX = e.clientX;
    startY = e.clientY;
    startFrequency = frequency;
    startModulation = modulationDepth;
    circle.style.display = 'flex';
    updateCircle();
  });

  document.addEventListener('mouseup', () => {
    isMouseDown = false;
    circle.style.display = 'none';
  });

  document.addEventListener('mousemove', (e) => {
    mouseX = e.clientX;
    mouseY = e.clientY;

    if (!isMouseDown) return;

    // Horizontal drag: frequency (1-50 Hz)
    const deltaX = e.clientX - startX;
    const pixelsPerHz = window.innerWidth / 49;
    frequency = Math.max(
      1,
      Math.min(50, startFrequency + deltaX / pixelsPerHz)
    );

    // Vertical drag: modulation depth (0-255)
    const deltaY = e.clientY - startY;
    const pixelsPerMod = window.innerHeight / 255;
    modulationDepth = Math.max(
      0,
      Math.min(255, startModulation - deltaY / pixelsPerMod)
    );

    updateCircle();
  });

  function updateCircle() {
    circle.style.left = mouseX + 'px';
    circle.style.top = mouseY + 'px';
    circle.innerHTML = `
      <div>${frequency.toFixed(1)}Hz</div>
      <div>${modulationDepth.toFixed(0)}</div>
    `;
  }

  function updateOverlay() {
    let text = `Frequency: ${frequency.toFixed(2)} Hz<br>`;
    text += `Modulation: ${modulationDepth.toFixed(0)} / 255<br>`;

    if (isAnimating) {
      text += `Drag left/right for frequency | Drag up/down for modulation<br>`;
      text += `Space to pause | ESC to close`;
    } else {
      text += `[PAUSED]<br>`;
      text += `Space to resume | ESC to close`;
    }

    overlay.innerHTML = text;
  }

  // ---------- animation ----------
  //
  // `ts` is the requestAnimationFrame timestamp: the display's vsync
  // instant for the frame about to be presented. Computing the phase
  // from it (instead of a continuous wall clock) makes every red/black
  // flip land exactly on a frame boundary.

  function frame(ts) {
    if (t0 < 0) t0 = ts;

    let r = 0;
    if (isAnimating) {
      const period = 1000 / frequency; // ms per full cycle
      if ((ts - t0) % period < period / 2) {
        r = modulationDepth / 255;
      }
    }

    gl.uniform3f(uColor, r, 0, 0);
    gl.drawArrays(gl.TRIANGLES, 0, 3);

    updateOverlay();
    rafId = requestAnimationFrame(frame);
  }
  rafId = requestAnimationFrame(frame);

  // ---------- keyboard ----------

  document.addEventListener('keydown', (e) => {
    if (stopped) return;
    if (e.key === ' ') {
      e.preventDefault();
      isAnimating = !isAnimating;
      if (isAnimating) t0 = -1; // restart the phase on the next frame
      console.log(isAnimating ? 'Resumed' : 'Paused');
    } else if (e.key === 'Escape') {
      stopped = true;
      cancelAnimationFrame(rafId);
      const lose = gl.getExtension('WEBGL_lose_context');
      if (lose) lose.loseContext();
      canvas.remove();
      overlay.remove();
      circle.remove();
      console.log('Ganzflicker stopped');
    }
  });

  console.log('Ganzflicker WebGL active!');
  console.log('Drag left/right to change frequency (1-40 Hz)');
  console.log('Drag up/down to change modulation depth (0-255)');
  console.log('Space to pause | ESC to close');
})();
