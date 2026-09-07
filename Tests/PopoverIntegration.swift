import AppKit
import SwiftUI

@main
enum PopoverIntegration {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        // Preview mode never starts display control or touches preferences.
        let delegate = AppDelegate(previewOnly: true)
        app.delegate = delegate
        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 800_000_000)
                _ = delegate.applicationShouldHandleReopen(app, hasVisibleWindows: false)
                try await Task.sleep(nanoseconds: 400_000_000)
                try check(delegate, stage: "initial show")
                let initialSize = delegate.testPopover.contentSize
                delegate.testPopover.contentSize.height += 90
                try await Task.sleep(nanoseconds: 500_000_000)
                try check(delegate, stage: "content grows")
                delegate.testPopover.contentSize = initialSize
                try await Task.sleep(nanoseconds: 500_000_000)
                try check(delegate, stage: "content shrinks")
                delegate.testPopover.close()
                _ = delegate.applicationShouldHandleReopen(app, hasVisibleWindows: false)
                try await Task.sleep(nanoseconds: 500_000_000)
                try check(delegate, stage: "reopened")
                delegate.testPopover.close()
                exit(0)
            } catch {
                delegate.testPopover.close()
                fputs("FAIL: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        withExtendedLifetime(delegate) { app.run() }
    }

    @MainActor static func check(_ delegate: AppDelegate, stage: String) throws {
        guard delegate.testPopover.isShown,
              let frame = delegate.testPopover.contentViewController?.view.window?.frame,
              let anchor = delegate.testAnchor else {
            throw NSError(domain: "PopoverTest", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No visible test menu: \(stage); anchor available: \(delegate.testAnchor != nil)"])
        }
        let gap = anchor.minY - frame.maxY
        guard abs(gap - 2) <= 1 else {
            throw NSError(domain: "PopoverTest", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Unexpected menu gap \(gap) pt: \(stage)"])
        }
        print("PASS: \(stage), menu gap \(gap) pt")
    }
}
