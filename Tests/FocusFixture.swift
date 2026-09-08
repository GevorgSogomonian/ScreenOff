import AppKit

/// A second, isolated app for real focus changes in the interface test.
/// It has no display controller, preferences, status item or Dock item.
@MainActor
final class FocusFixtureDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 220, height: 80),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "ScreenOff focus test"
        window.isReleasedWhenClosed = false
        self.window = window
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

@main
enum FocusFixture {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = FocusFixtureDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
