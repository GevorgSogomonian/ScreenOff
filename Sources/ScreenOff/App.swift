import AppKit
import SwiftUI
import Combine
import Darwin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var controller: DisplayController?
    private var observation: AnyCancellable?
    private var terminationStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = DisplayController()
        self.controller = controller
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "ScreenOff")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePopover)
            button.toolTip = "ScreenOff — встроенный дисплей"
            button.setAccessibilityLabel("ScreenOff")
        }
        popover.behavior = .transient
        popover.animates = true
        let host = NSHostingController(rootView: MenuView(controller: controller) { NSApp.terminate(nil) })
        popover.contentViewController = host
        observation = controller.$snapshot.sink { [weak self] snapshot in
            let name = snapshot.builtInIsOn ? "laptopcomputer" : "display"
            self?.statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "ScreenOff")
            self?.statusItem?.button?.image?.isTemplate = true
        }
        controller.start()
        if !controller.automatic {
            DispatchQueue.main.async { [weak self] in self?.showPopover() }
        }
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        showPopover()
    }

    private func showPopover() {
        guard !popover.isShown else { return }
        guard let button = statusItem?.button else { return }
        controller?.updateLoginNotice()
        controller?.requestEvaluation()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationStarted else { return .terminateLater }
        terminationStarted = true
        popover.performClose(nil)
        Task {
            _ = await controller?.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
enum ScreenOffApp {
    @MainActor static func main() {
        signal(SIGPIPE, SIG_IGN)
        let arguments = CommandLine.arguments
        if arguments.contains("--diagnose") {
            let hardware = DisplayHardware()
            do {
                let snapshot = try hardware.snapshot()
                let data = try JSONEncoder().encode(snapshot)
                print("ScreenOff 1.0.0 | \(ProcessInfo.processInfo.operatingSystemVersionString)")
                print("Disconnect API: \(hardware.resolvedSymbol ?? "unavailable")")
                print(String(decoding: data, as: UTF8.self))
                exit(hardware.supported ? 0 : 2)
            } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
        }
        if arguments.contains("--recover") {
            _ = NSApplication.shared
            DistributedNotificationCenter.default().postNotificationName(
                DisplayController.recoverNotification, object: nil, userInfo: nil, deliverImmediately: true)
            let restored = DisplayHardware().recover()
            print(restored ? "Built-in display restored." : "Recovery failed. Close and reopen the lid, or reconnect the external display.")
            exit(restored ? 0 : 1)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        if arguments.contains("--hardware-test") {
            Task { @MainActor in
                let controller = DisplayController(testing: true)
                do {
                    try await controller.hardwareTest()
                    exit(0)
                } catch {
                    fputs("FAIL: \(error.localizedDescription)\n", stderr)
                    exit(1)
                }
            }
            app.run()
            return
        }
        // A second launch should reopen the existing menu, never compete over
        // display state or start a second automation controller.
        if let id = Bundle.main.bundleIdentifier,
           let other = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .first(where: { $0.processIdentifier != getpid() }) {
            other.activate(options: [.activateIgnoringOtherApps])
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
