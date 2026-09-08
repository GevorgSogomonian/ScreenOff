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
        let delegate = AppDelegate(previewOnly: true, backgroundLaunch: true)
        app.delegate = delegate
        Task { @MainActor in
            await pause()
            expect(delegate.testSettingsWindow == nil && !app.windows.contains(where: \.isVisible),
                   "background startup creates no visible windows")
            expect(app.activationPolicy() == .accessory,
                   "background application has no Dock item")
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
            expect(window.isVisible && window.isKeyWindow,
                   "reopen brings settings to the foreground")
            expect(app.activationPolicy() == .accessory &&
                   !app.windows.contains(where: { $0.level == .statusBar }),
                   "opening settings creates no Dock item or status bar window")
            expect(!window.styleMask.contains(.miniaturizable),
                   "settings cannot be minimized into the Dock")
            let content = window.contentView!
            expect(content.bounds.width >= content.fittingSize.width && content.bounds.height >= content.fittingSize.height,
                   "settings window fits the complete content")
            // deactivate() alone can immediately reactivate the frontmost app.
            // Give focus to a separate app to exercise AppKit's real behavior.
            let fixtureURL = Bundle.main.bundleURL.deletingLastPathComponent()
                .appendingPathComponent("ScreenOffFocusFixture.app")
            let fixture: NSRunningApplication
            do {
                fixture = try await NSWorkspace.shared.openApplication(at: fixtureURL,
                                                                       configuration: configuration)
            } catch {
                fatalError("Focus fixture launch failed: \(error)")
            }
            await pause()
            expect(fixture.isActive && !app.isActive && !window.occlusionState.contains(.visible),
                   "switching to another app removes settings from the screen")
            do {
                let reopened = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL,
                                                                            configuration: configuration)
                expect(reopened.processIdentifier == getpid(), "reopen after deactivation keeps the same process")
            } catch {
                fatalError("LaunchServices reopen after deactivation failed: \(error)")
            }
            await pause()
            expect(delegate.testSettingsWindow === window && window.isKeyWindow &&
                   window.occlusionState.contains(.visible),
                   "reopen restores the same settings window after automatic hiding")
            expect(fixture.terminate(), "isolated focus fixture terminates normally")
            let originalWindow = window
            window.performClose(nil)
            expect(!window.isVisible && !delegate.applicationShouldTerminateAfterLastWindowClosed(app),
                   "closing settings leaves the background app running")
            do {
                let reopened = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL,
                                                                            configuration: configuration)
                expect(reopened.processIdentifier == getpid(), "relaunch after closing keeps the same process")
            } catch {
                fatalError("LaunchServices second reopen failed: \(error)")
            }
            await pause()
            expect(delegate.testSettingsWindow === originalWindow && window.isVisible,
                   "reopening reuses the same settings window")
            expect(app.activationPolicy() == .accessory &&
                   app.windows.filter(\.isVisible).count == 1,
                   "repeated reopen leaves one window and no Dock item")
            window.orderOut(nil)
            print("PASS: \(checks) native interface checks; no display transactions")
            exit(0)
        }
        withExtendedLifetime(delegate) { app.run() }
    }
}
