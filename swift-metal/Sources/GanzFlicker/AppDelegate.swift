import AppKit
import CoreVideo

// Raw CVDisplayLink probe (GF_DIAG): @convention(c) callbacks may only
// touch globals.
fileprivate var gfCVTickCount = 0
fileprivate let gfCVCallback: @convention(c) (
    CVDisplayLink,
    UnsafePointer<CVTimeStamp>,
    UnsafePointer<CVTimeStamp>,
    UInt64,
    UnsafeMutablePointer<UInt64>,
    UnsafeMutableRawPointer?
) -> Int32 = { _, _, _, _, _, _ in
    gfCVTickCount += 1
    return 0 // kCVReturnSuccess
}

/// Borderless windows cannot become key by default; key status is required
/// for `keyDown` (ESC to quit) to be delivered to the content view.
final class FlickerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: FlickerWindow!
    private var flickerView: FlickerView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Headless smoke test: `GF_SMOKE_TEST=1` verifies shader compilation
        // and pipeline creation, then exits without taking over the screen.
        if ProcessInfo.processInfo.environment["GF_SMOKE_TEST"] != nil {
            _ = FlickerView(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
            NSLog("GanzFlicker smoke test: Metal shader + pipeline OK")
            NSApp.terminate(nil)
            return
        }

        guard let screen = NSScreen.main else {
            NSLog("GanzFlicker: no main screen available")
            NSApp.terminate(nil)
            return
        }

        let frame = screen.frame
        flickerView = FlickerView(frame: frame)

        window = FlickerWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.isMovable = false
        window.level = .statusBar            // above the menu-bar region
        window.acceptsMouseMovedEvents = true
        window.contentView = flickerView
        window.delegate = self
        window.makeFirstResponder(flickerView)

        // A fullscreen app must steal focus for real: the non-forceful
        // macOS 14 `activate()` refuses to come forward while the
        // launching terminal still has focus, leaving the window
        // non-key. MTKView's render loop doesn't start until the window
        // is key — so the screen stays solid black and ESC never works.
        NSApp.activate(ignoringOtherApps: true)

        // Fullscreen presentation: no menu bar, no dock.
        NSApp.presentationOptions = [.hideMenuBar, .hideDock]

        window.makeKeyAndOrderFront(nil)

        // No window frame and no cursor.
        NSCursor.hide()

        // GF_DIAG: real launch, then a render-pipeline report after 5 s.
        // GF_DIAG_BLACK forces the off state (solid black, zero flashing)
        // so the diagnostic can be run safely unattended.
        if ProcessInfo.processInfo.environment["GF_DIAG"] != nil {
            if ProcessInfo.processInfo.environment["GF_DIAG_BLACK"] != nil {
                flickerView.setRunning(false)
            }
            // Control: a raw Core Video display link independent of the
            // view's own, to prove vsync delivery in this process.
            var cvLink: CVDisplayLink?
            let cvStatus = CVDisplayLinkCreateWithActiveCGDisplays(&cvLink)
            if let cvLink = cvLink {
                CVDisplayLinkSetOutputCallback(
                    cvLink,
                    gfCVCallback,
                    nil as UnsafeMutableRawPointer?
                )
                CVDisplayLinkStart(cvLink)
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, let v = self.flickerView,
                      let w = self.window else { return }
                var cvTicks = gfCVTickCount
                if let cvLink = cvLink {
                    CVDisplayLinkStop(cvLink)
                    cvTicks = gfCVTickCount
                }
                let deviceName = v.device?.name ?? "none"
                let guardFailure = v.lastGuardFailure ?? "none"
                let lines = [
                    "===== GF_DIAG report =====",
                    "frames draw() called:   \(v.frameCount)",
                    "frames presented:       \(v.presentCount)",
                    "view cv-link ticks:     \(v.cvTickCount)",
                    "raw CVDisplayLink ticks: \(cvTicks) (create status \(cvStatus))",
                    "last guard failure:     \(guardFailure)",
                    "state: isRunning=\(v.isRunning) red=\(v.red) freq=\(v.frequency) phase=\(v.phase)",
                    "view bounds: \(v.bounds)  drawableSize: \(v.drawableSize)",
                    "layer contentsScale: \(v.layer?.contentsScale ?? -1)",
                    "isPaused: \(v.isPaused)  preferredFPS: \(v.preferredFramesPerSecond)",
                    "window key/visible/screen: \(w.isKeyWindow)/\(w.isVisible)/\(w.screen != nil)  level=\(w.level.rawValue)",
                    "NSApp isActive: \(NSApp.isActive)",
                    "pixelFormat raw: \(v.colorPixelFormat.rawValue)  device: \(deviceName)"
                ]
                print(lines.joined(separator: "\n"))
                NSApp.terminate(nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
        }
    }

    // Restore the cursor if the app resigns the key window (⌘-tab,
    // Mission Control); re-hide it when it comes back.
    func windowDidResignKey(_ notification: Notification) {
        NSCursor.unhide()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        NSCursor.hide()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSCursor.unhide()
    }
}
