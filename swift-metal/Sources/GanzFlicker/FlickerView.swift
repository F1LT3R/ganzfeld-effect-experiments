import AppKit
import Metal
import MetalKit

// MARK: - Metal shader
//
// Fullscreen triangle + fragment shader. The fragment outputs pure red or
// black from a fractional square-wave phase. `r` is the red channel in
// 100...255; `running` == 0 forces solid black (animation off).

private let mslSource = """
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float r;       // red channel, 100...255
    float phase;   // fractional square-wave phase
    float running; // 1 = animation on, 0 = off
};

vertex float4 fullscreenTriangle(uint vid [[vertex_id]]) {
    float2 p[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };
    return float4(p[vid], 0.0, 1.0);
}

fragment float4 flicker(constant Uniforms &u [[buffer(0)]]) {
    if (u.running < 0.5) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    float3 color = fract(u.phase) < 0.5
        ? float3(u.r / 255.0, 0.0, 0.0)
        : float3(0.0, 0.0, 0.0);
    return float4(color, 1.0);
}
"""

// MARK: - FlickerView
//
// An `MTKView` (an `NSView`) that acts as its own `MTKViewDelegate`: owns
// the Metal pipeline and render loop, handles all mouse/key input, and
// draws the status bar on top of the flicker surface.

/// A view that lets all mouse events fall through to the Metal view
/// underneath (so clicks on the status bar still toggle the animation).
private final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class PassthroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class FlickerView: MTKView, MTKViewDelegate {

    // MARK: Tunables (defaults per SPEC.md)

    private static let rRange = 100...255
    private static let frequencyRange = 1.0...50.0

    private(set) var red: Int = 150      // red channel, 100...255
    private(set) var frequency: Double = 7.5 // Hz, 1.0...50.0
    private(set) var isRunning: Bool = true

    // MARK: Render loop (raw CVDisplayLink)
    //
    // AppKit's NSView/NSWindow/NSScreen.displayLink(target:selector:) never
    // fires in this SDK/OS combination (verified with GF_DIAG), and
    // MTKView's internal loop relies on it — so the render loop is driven
    // by a raw CVDisplayLink: its callback (background thread, once per
    // vsync at the display's native rate) enqueues one coalesced draw()
    // on the main queue, which calls back into draw(in:) below.

    private var cvLink: CVDisplayLink?
    private let renderGate = DispatchSemaphore(value: 1)

    // MARK: Diagnostics (GF_DIAG)

    private(set) var frameCount = 0     // draw(in:) invocations
    private(set) var presentCount = 0   // frames actually presented
    private(set) var cvTickCount = 0    // CVDisplayLink callback invocations
    private(set) var lastGuardFailure: String?

    /// Square-wave phase accumulator kept in [0, 1). Advances by
    /// `deltaTime * frequency` each frame, so changing the frequency
    /// never causes a phase jump.
    private(set) var phase: Double = 0
    private var lastFrameTime: CFTimeInterval?

    private var lastMouseLocation: NSPoint?

    // MARK: Metal

    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let uniformBuffer: MTLBuffer

    /// Mirrors the MSL `Uniforms` struct (3 floats, 12 bytes).
    private struct Uniforms {
        var r: Float
        var phase: Float
        var running: Float
    }

    // MARK: Status bar

    private static let statusBarHeight: CGFloat = 20
    private let statusBar: NSView
    private let statusLabel: NSTextField

    // MARK: Init

    init(frame frameRect: NSRect) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: mslSource, options: nil),
              let vertexFunction = library.makeFunction(name: "fullscreenTriangle"),
              let fragmentFunction = library.makeFunction(name: "flicker")
        else {
            fatalError("GanzFlicker: failed to compile Metal shaders")
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(
            descriptor: pipelineDescriptor
        ) else {
            fatalError("GanzFlicker: failed to build render pipeline")
        }
        guard let uniformBuffer = device.makeBuffer(
            length: MemoryLayout<Uniforms>.stride,
            options: []
        ) else {
            fatalError("GanzFlicker: failed to allocate uniform buffer")
        }

        // Status bar: semi-transparent black strip with an 8 pt white
        // monospaced label. Clicks pass through to the Metal view.
        let bar = PassthroughView(frame: NSRect(
            x: 0, y: 0,
            width: frameRect.width, height: Self.statusBarHeight
        ))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(white: 0, alpha: 0.6).cgColor
        bar.autoresizingMask = [.width, .maxYMargin]

        let label = PassthroughLabel(labelWithString: "")
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .white
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        bar.addSubview(label)

        self.statusBar = bar
        self.statusLabel = label
        self.commandQueue = queue
        self.pipeline = pipeline
        self.uniformBuffer = uniformBuffer

        super.init(frame: frameRect, device: device)

        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        framebufferOnly = true
        preferredFramesPerSecond = 0
        enableSetNeedsDisplay = false
        delegate = self

        // Start the raw CVDisplayLink (once per vsync, display's native
        // rate). If it cannot be created, fall back to MTKView's internal
        // render loop.
        var link: CVDisplayLink?
        if CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess,
           let link {
            CVDisplayLinkSetOutputCallback(
                link,
                Self.cvDisplayCallback,
                Unmanaged.passUnretained(self).toOpaque()
            )
            CVDisplayLinkStart(link)
            cvLink = link
            isPaused = true // we drive the render loop ourselves
        } else {
            isPaused = false // let MTKView's internal loop render
        }

        addSubview(statusBar)
        updateStatusBar()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        if let cvLink = cvLink {
            CVDisplayLinkStop(cvLink)
        }
    }

    /// CVDisplayLink output callback — runs on a background thread once
    /// per vsync. Enqueues at most one in-flight draw on the main queue
    /// (coalesced via renderGate); MTKView.draw() then calls back into
    /// the delegate's draw(in:).
    private static let cvDisplayCallback: @convention(c) (
        CVDisplayLink,
        UnsafePointer<CVTimeStamp>,
        UnsafePointer<CVTimeStamp>,
        UInt64,
        UnsafeMutablePointer<UInt64>,
        UnsafeMutableRawPointer?
    ) -> Int32 = { _, _, _, _, _, context in
        guard let context = context else { return 0 }
        let view = Unmanaged<FlickerView>.fromOpaque(context)
            .takeUnretainedValue()
        view.cvTickCount += 1
        if view.renderGate.wait(timeout: .now()) == .success {
            DispatchQueue.main.async {
                view.draw()
                view.renderGate.signal()
            }
        }
        return 0 // kCVReturnSuccess
    }

    // MARK: Responder

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        // Intentionally empty: the hardware cursor stays hidden
        // (NSCursor.hide in AppDelegate).
    }

    // MARK: Mouse input

    override func mouseMoved(with event: NSEvent) {
        handleMove(event)
    }

    override func mouseDragged(with event: NSEvent) {
        handleMove(event)
    }

    private func handleMove(_ event: NSEvent) {
        let location = event.locationInWindow
        defer { lastMouseLocation = location }
        guard let last = lastMouseLocation else { return }

        // Window coordinates: x grows rightward, y grows upward on screen.
        let dyUp = location.y - last.y     // +1 per pixel moved up
        let dxRight = location.x - last.x  // +1 per pixel moved right

        if dyUp != 0 {
            red = (red + Int(dyUp.rounded())).clamped(to: Self.rRange)
        }
        if dxRight != 0 {
            frequency = (frequency + dxRight * 0.1)
                .clamped(to: Self.frequencyRange)
        }
        updateStatusBar()
    }

    override func mouseDown(with event: NSEvent) {
        guard event.buttonNumber == 0 else { return }
        // Toggle the animation. Toggling never resets the phase accumulator.
        setRunning(!isRunning)
    }

    /// Toggle the animation on/off (mouse click, diagnostics).
    func setRunning(_ running: Bool) {
        isRunning = running
        updateStatusBar()
    }

    // MARK: Keyboard input

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // ESC — quit
            NSApp.terminate(nil)
        default:
            break
        }
    }

    // MARK: Status bar

    private func updateStatusBar() {
        statusLabel.stringValue = String(
            format: "freq: %.1f Hz   red: %d",
            frequency, red
        )
        statusLabel.sizeToFit()
        let barHeight = statusBar.bounds.height
        statusLabel.frame.origin = NSPoint(
            x: 8,
            y: (barHeight - statusLabel.frame.height) / 2
        )
    }

    override func layout() {
        super.layout()
        let height = Self.statusBarHeight
        statusBar.frame = NSRect(
            x: 0,
            y: isFlipped ? bounds.maxY - height : 0,
            width: bounds.width,
            height: height
        )
        statusLabel.sizeToFit()
        statusLabel.frame.origin = NSPoint(
            x: 8,
            y: (height - statusLabel.frame.height) / 2
        )
    }

    // MARK: MTKViewDelegate

    // The drawable is auto-resized by MTKView at the view's native
    // resolution (autoResizeDrawable defaults to true), so no per-size
    // bookkeeping is needed.
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Intentionally empty: see note above.
    }

    func draw(in view: MTKView) {
        frameCount += 1

        // Frame delta, clamped so a long hitch (sleep, Mission Control)
        // cannot lurch the phase.
        let now = CACurrentMediaTime()
        let deltaTime = min(now - (lastFrameTime ?? now), 1.0 / 15.0)
        lastFrameTime = now

        if isRunning {
            phase += deltaTime * frequency
            if phase >= 1.0 {
                phase -= phase.rounded(.down) // keep in [0, 1)
            }
        }

        var uniforms = Uniforms(
            r: Float(red),
            phase: Float(phase),
            running: isRunning ? 1 : 0
        )
        memcpy(
            uniformBuffer.contents(),
            &uniforms,
            MemoryLayout<Uniforms>.stride
        )

        guard
            let renderPass = view.currentRenderPassDescriptor
        else {
            lastGuardFailure = "currentRenderPassDescriptor nil"
            return
        }
        guard let drawable = view.currentDrawable else {
            lastGuardFailure = "currentDrawable nil"
            return
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            lastGuardFailure = "makeCommandBuffer nil"
            return
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: renderPass
        ) else {
            lastGuardFailure = "makeRenderCommandEncoder nil"
            return
        }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
        presentCount += 1
    }
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
