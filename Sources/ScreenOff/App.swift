import AppKit
import SwiftUI
import Combine
import Darwin
import CoreServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var controller: DisplayController?
    private var observation: AnyCancellable?
    private var visibilityObservation: AnyCancellable?
    private var contentObservation: AnyCancellable?
    private var settingsWindow: NSWindow?
    private var settingsHost: NSHostingController<MenuView>?
    private let interface: InterfacePreferences
    private var terminationStarted = false
    private var popoverObservers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private let previewOnly: Bool
    private let restoreOnLaunch: Bool
    private let backgroundLaunch: Bool
    private var launchedAtLogin = false

    static var showSettingsNotification: Notification.Name {
        Notification.Name((Bundle.main.bundleIdentifier ?? "com.gevorg.screenoff") + ".showSettings")
    }

    init(previewOnly: Bool = false, restoreOnLaunch: Bool = false,
         backgroundLaunch: Bool = false, interface: InterfacePreferences? = nil) {
        self.previewOnly = previewOnly
        self.restoreOnLaunch = restoreOnLaunch
        self.backgroundLaunch = backgroundLaunch
        self.interface = interface ?? InterfacePreferences(preferences: previewOnly ? nil : .standard)
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        launchedAtLogin = Self.isLoginLaunch()
    }

    private static func isLoginLaunch() -> Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        return event?.eventID == kAEOpenApplication &&
            event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = DisplayController(testing: previewOnly, previewOnly: previewOnly)
        self.controller = controller
        popover.behavior = previewOnly ? .applicationDefined : .transient
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: makeMenuView(controller))
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
        observation = controller.$snapshot.map(\.builtInIsOn).removeDuplicates().sink { [weak self] on in
            let name = on ? "laptopcomputer" : "display"
            self?.statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "ScreenOff")
            self?.statusItem?.button?.image?.isTemplate = true
        }
        visibilityObservation = interface.$statusItemHidden.sink { [weak self] hidden in
            self?.updateStatusItem(hidden: hidden)
        }
        contentObservation = controller.objectWillChange
            .debounce(for: .milliseconds(20), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                guard self?.settingsWindow?.isVisible == true else { return }
                self?.resizeSettingsWindow()
        }
        if !previewOnly {
            DistributedNotificationCenter.default().addObserver(
                self, selector: #selector(openSettings), name: Self.showSettingsNotification, object: nil)
            // A safe update/recovery launch preserves the saved automatic
            // switch while keeping the panel on until an explicit user choice.
            if restoreOnLaunch { controller.setBuiltIn(on: true) }
            controller.start()
        }
        if !previewOnly && !backgroundLaunch && !launchedAtLogin && !Self.isLoginLaunch() {
            DispatchQueue.main.async { [weak self] in self?.showSettingsWindow() }
        }
    }

    private func makeMenuView(_ controller: DisplayController) -> MenuView {
        MenuView(controller: controller, interface: interface,
                 changeVisibility: { [weak self] in self?.changeStatusItemVisibility() },
                 quit: { NSApp.terminate(nil) })
    }

    private func updateStatusItem(hidden: Bool) {
        if hidden {
            // Finish closing before destroying its anchor. An animated close
            // can leave an orphaned popover after the status window disappears.
            let animated = popover.animates
            popover.animates = false
            popover.close()
            popover.animates = animated
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
        } else if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            statusItem = item
            if let button = item.button {
                let name = controller?.snapshot.builtInIsOn == false ? "display" : "laptopcomputer"
                button.image = NSImage(systemSymbolName: name, accessibilityDescription: "ScreenOff")
                button.image?.isTemplate = true
                button.target = self
                button.action = #selector(togglePopover)
                button.toolTip = "ScreenOff — встроенный дисплей"
                button.setAccessibilityLabel("ScreenOff")
            }
        }
    }

    private func changeStatusItemVisibility() {
        let hidden = !interface.statusItemHidden
        interface.setStatusItemHidden(hidden)
        // Keep the controls reachable immediately after removing their anchor.
        if hidden { showSettingsWindow() }
    }

    @objc private func openSettings() { showSettingsWindow() }

    private func showSettingsWindow() {
        guard let controller, !terminationStarted else { return }
        popover.performClose(nil)
        if !previewOnly {
            controller.updateLoginNotice()
            controller.requestEvaluation()
        }
        if settingsWindow == nil {
            let host = NSHostingController(rootView: makeMenuView(controller))
            host.sizingOptions = [.preferredContentSize]
            settingsHost = host
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 374, height: 300),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "ScreenOff"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.collectionBehavior = [.moveToActiveSpace]
            window.contentViewController = host
            settingsWindow = window
            resizeSettingsWindow()
            window.center()
        }
        guard let window = settingsWindow else { return }
        if !window.isVisible { window.center() }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in self?.resizeSettingsWindow() }
    }

    private func resizeSettingsWindow() {
        guard let window = settingsWindow, let host = settingsHost else { return }
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        let current = window.contentLayoutRect.size
        guard abs(current.width - size.width) > 0.5 || abs(current.height - size.height) > 0.5 else { return }
        let top = window.frame.maxY
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height))
        window.setFrame(window.constrainFrameRect(window.frame, to: window.screen), display: true)
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
        showSettingsWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationStarted else { return .terminateLater }
        terminationStarted = true
        popover.performClose(nil)
        removePopoverObservers()
        settingsWindow?.orderOut(nil)
        DistributedNotificationCenter.default().removeObserver(self)
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
    var testSettingsWindow: NSWindow? { settingsWindow }
    var testStatusItemExists: Bool { statusItem != nil }
    func testShowPopover() { showPopover() }
    func testChangeVisibility() { changeStatusItemVisibility() }
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
        // A second launch should open the existing settings window, never compete over
        // display state or start a second automation controller.
        if let id = Bundle.main.bundleIdentifier,
           let other = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .first(where: { $0.processIdentifier != getpid() }) {
            DistributedNotificationCenter.default().postNotificationName(
                AppDelegate.showSettingsNotification, object: nil, userInfo: nil, deliverImmediately: true)
            other.activate(options: [])
            return
        }
        let delegate = AppDelegate(restoreOnLaunch: arguments.contains("--restore-on-launch"),
                                   backgroundLaunch: arguments.contains("--background"))
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
#endif
