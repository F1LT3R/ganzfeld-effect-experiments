import AppKit

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

        window.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }

        // Fullscreen presentation: no menu bar, no dock.
        NSApp.presentationOptions = [.hideMenuBar, .hideDock]

        // No window frame and no cursor.
        NSCursor.hide()
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
