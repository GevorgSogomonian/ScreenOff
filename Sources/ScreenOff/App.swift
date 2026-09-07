import AppKit
import SwiftUI
import Combine
import Darwin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var controller: DisplayController?
    private var observation: AnyCancellable?
    private var terminationStarted = false
    private var popoverObservers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private let previewOnly: Bool
    private let restoreOnLaunch: Bool

    init(previewOnly: Bool = false, restoreOnLaunch: Bool = false) {
        self.previewOnly = previewOnly
        self.restoreOnLaunch = restoreOnLaunch
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = DisplayController(testing: previewOnly)
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
        popover.behavior = previewOnly ? .applicationDefined : .transient
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: MenuView(controller: controller) { NSApp.terminate(nil) })
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // The status item's window may migrate to another screen/scale.
            // Discard the old native anchor; the next click resolves it afresh.
            MainActor.assumeIsolated {
                guard let self, !self.previewOnly else { return }
                self.popover.performClose(nil)
            }
        }
        observation = controller.$snapshot.sink { [weak self] snapshot in
            let name = snapshot.builtInIsOn ? "laptopcomputer" : "display"
            self?.statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "ScreenOff")
            self?.statusItem?.button?.image?.isTemplate = true
        }
        if !previewOnly {
            // A safe update/recovery launch preserves the saved automatic
            // switch while keeping the panel on until an explicit user choice.
            if restoreOnLaunch { controller.setBuiltIn(on: true) }
            controller.start()
        }
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
        if !previewOnly {
            controller?.updateLoginNotice()
            controller?.requestEvaluation()
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        alignPopover()
        DispatchQueue.main.async { [weak self] in self?.alignPopover() }
    }

    func popoverDidShow(_ notification: Notification) {
        removePopoverObservers()
        guard let window = popover.contentViewController?.view.window else { return }
        popoverObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main
        ) { [weak self] _ in
            // Reanchor after AppKit completes its resize. Otherwise shortening
            // a login/status message can leave a large gap below the menu bar.
            DispatchQueue.main.async { self?.alignPopover() }
        })
        alignPopover()
    }

    func popoverDidClose(_ notification: Notification) { removePopoverObservers() }

    private func removePopoverObservers() {
        for observer in popoverObservers { NotificationCenter.default.removeObserver(observer) }
        popoverObservers.removeAll()
    }

    private func alignPopover() {
        guard popover.isShown,
              let button = statusItem?.button, let buttonWindow = button.window,
              let screen = buttonWindow.screen,
              let window = popover.contentViewController?.view.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let origin = PopoverPlacement.origin(frame: window.frame, anchor: anchor, screen: screen.frame)
        if abs(window.frame.minX - origin.x) > 0.5 || abs(window.frame.minY - origin.y) > 0.5 {
            window.setFrameOrigin(origin)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationStarted else { return .terminateLater }
        terminationStarted = true
        popover.performClose(nil)
        removePopoverObservers()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        Task {
            _ = await controller?.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

#if POPOVER_TEST
extension AppDelegate {
    var testPopover: NSPopover { popover }
    var testAnchor: NSRect? {
        guard let button = statusItem?.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }
}
#else
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
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
                print("ScreenOff \(version) | \(ProcessInfo.processInfo.operatingSystemVersionString)")
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
        let delegate = AppDelegate(restoreOnLaunch: arguments.contains("--restore-on-launch"))
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
#endif
