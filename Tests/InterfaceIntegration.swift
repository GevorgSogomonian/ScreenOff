import AppKit
import SwiftUI

/// Runs the production UI in a separate, preview-only app bundle. All launch
/// requests target this bundle, never the installed ScreenOff or its settings.
@main
enum InterfaceIntegration {
    @MainActor static var checks = 0

    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError("FAIL: \(message)") }
        print("PASS: \(message)")
    }

    @MainActor static func pause() async {
        try? await Task.sleep(nanoseconds: 450_000_000)
    }

    @MainActor static func main() {
        setbuf(stdout, nil)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let suite = "com.gevorg.screenoff.interface-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let preferences = InterfacePreferences(preferences: defaults)
        expect(!preferences.statusItemHidden, "fresh preferences show the icon")
        preferences.setStatusItemHidden(true)
        let reloaded = InterfacePreferences(preferences: defaults)
        expect(reloaded.statusItemHidden, "hidden preference survives model recreation")
        let delegate = AppDelegate(previewOnly: true, backgroundLaunch: true, interface: reloaded)
        app.delegate = delegate
        Task { @MainActor in
            await pause()
            expect(!delegate.testStatusItemExists && delegate.testSettingsWindow == nil,
                   "hidden background startup creates neither icon nor window")
            // NSWorkspace sends the same LaunchServices reopen event used by
            // Spotlight/Finder. It must target this already-running process.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            do {
                let reopened = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL,
                                                                            configuration: configuration)
                expect(reopened.processIdentifier == getpid(), "LaunchServices reuses the running process")
            } catch {
                fatalError("LaunchServices reopen failed: \(error)")
            }
            await pause()
            guard let window = delegate.testSettingsWindow else { fatalError("Reopen did not create settings") }
            expect(window.isVisible && !delegate.testStatusItemExists,
                   "reopen displays settings while keeping the icon hidden")
            let content = window.contentView!
            expect(content.bounds.width >= content.fittingSize.width && content.bounds.height >= content.fittingSize.height,
                   "settings window fits the complete content")
            let originalWindow = window
            window.performClose(nil)
            expect(!window.isVisible && !delegate.applicationShouldTerminateAfterLastWindowClosed(app),
                   "closing settings leaves the background app running")
            _ = delegate.applicationShouldHandleReopen(app, hasVisibleWindows: false)
            await pause()
            expect(delegate.testSettingsWindow === originalWindow && window.isVisible,
                   "reopening reuses the same settings window")
            delegate.testChangeVisibility()
            await pause()
            expect(delegate.testStatusItemExists && !InterfacePreferences(preferences: defaults).statusItemHidden,
                   "show button restores the icon and persists visibility")
            window.orderOut(nil)
            delegate.testShowPopover()
            await pause()
            expect(delegate.testPopover.isShown, "restored status item opens its popover")
            delegate.testChangeVisibility()
            await pause()
            expect(!delegate.testPopover.isShown && !delegate.testStatusItemExists && window.isVisible,
                   "hiding from the popover removes the anchor and opens settings")
            defaults.removePersistentDomain(forName: suite)
            window.orderOut(nil)
            print("PASS: \(checks) native interface checks; no display transactions")
            exit(0)
        }
        withExtendedLifetime(delegate) { app.run() }
    }
}
