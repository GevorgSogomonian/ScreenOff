import AppKit
import Combine
import CoreGraphics
import ServiceManagement

@MainActor
final class DisplayController: ObservableObject {
    @Published private(set) var snapshot = DisplaySnapshot(displays: [], lidClosed: false)
    @Published private(set) var automatic = false
    @Published private(set) var busy = false
    @Published private(set) var notice: String?
    @Published private(set) var loginNotice: String?
    let hardware = DisplayHardware()
    private let guardProcess = RecoveryGuard()
    private var policy: DisplayPolicy
    private let preferences: UserDefaults
    private var timer: Timer?
    private var evaluation: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var asleep = false
    private var stopping = false
    private var notBefore = Date.distantPast
    private var hasDisabled = false
    private var registeredCallback = false
    private var guardExpected = false
    static let recoverNotification = Notification.Name("com.gevorg.screenoff.restore")

    init(preferences: UserDefaults = .standard, testing: Bool = false) {
        self.preferences = preferences
        let saved = !testing && preferences.bool(forKey: "automaticDisplayOff")
        policy = DisplayPolicy(automatic: saved)
        automatic = saved
        if !hardware.supported {
            notice = DisplayFailure.unavailable("API отключения дисплея").localizedDescription
        }
        snapshot = (try? hardware.snapshot()) ?? snapshot
    }

    var canToggle: Bool {
        hardware.supported && !busy && !snapshot.lidClosed && snapshot.builtIn != nil
            && (!snapshot.builtInIsOn || snapshot.canDisable)
    }

    var statusText: String {
        if let notice { return notice }
        if busy { return "Переключение дисплея…" }
        if snapshot.lidClosed { return "Крышка MacBook закрыта" }
        if snapshot.builtIn == nil { return "Встроенный дисплей не найден" }
        if snapshot.displays.contains(where: { $0.online && $0.mirrored }) {
            return "Для отключения экрана выключите видеоповтор в macOS"
        }
        if snapshot.externalDisplays.isEmpty { return "Подключите внешний монитор" }
        return snapshot.builtInIsOn ? "Встроенный дисплей включён" : "Работает только внешний дисплей"
    }

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        registeredCallback = CGDisplayRegisterReconfigurationCallback(displayChanged, context) == .success
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.requestEvaluation() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.prepareForSleep() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.asleep = false
                self.notBefore = Date().addingTimeInterval(4)
                self.requestEvaluation()
            }
        })
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(emergencyRestore),
                                                            name: Self.recoverNotification, object: nil)
        updateLoginNotice()
        requestEvaluation()
    }

    func displaysChanged() {
        // Let link training and WindowServer reconfiguration settle. The helper
        // independently restores immediately if the last external disappears.
        notBefore = max(notBefore, Date().addingTimeInterval(0.8))
        requestEvaluation()
    }

    func setBuiltIn(on: Bool) {
        guard !busy else { return }
        policy.setManual(on: on)
        notice = nil
        notBefore = .distantPast
        requestEvaluation()
    }

    func setAutomatic(_ enabled: Bool) {
        policy.setAutomatic(enabled)
        automatic = enabled
        preferences.set(enabled, forKey: "automaticDisplayOff")
        notice = nil
        // This is part of automatic mode, keeping the interface at two toggles.
        // Manual mode remains available after the user removes the login item.
        do {
            if enabled && SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            } else if !enabled && SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
            updateLoginNotice()
        } catch {
            loginNotice = "Автозапуск: добавьте ScreenOff в Системные настройки → Основные → Объекты входа."
        }
        notBefore = .distantPast
        requestEvaluation()
    }

    func updateLoginNotice() {
        guard automatic else { loginNotice = nil; return }
        switch SMAppService.mainApp.status {
        case .enabled: loginNotice = nil
        case .requiresApproval:
            loginNotice = "Разрешите ScreenOff в Системных настройках → Основные → Объекты входа."
        default:
            loginNotice = "Для работы после перезагрузки добавьте ScreenOff в Объекты входа macOS."
        }
    }

    func requestEvaluation() {
        guard !stopping, !asleep, evaluation == nil else { return }
        evaluation = Task { [weak self] in
            guard let self else { return }
            defer { self.evaluation = nil }
            do {
                self.snapshot = try self.hardware.snapshot()
                // Restoration never waits for a debounce timer.
                let desired = self.policy.wantsBuiltInOn(for: self.snapshot)
                if self.guardExpected && !self.guardProcess.isRunning && self.hasDisabled && !desired {
                    self.policy.stopAfterFailure()
                    self.notice = "Защита восстановила экран. Для повторного отключения используйте переключатель."
                    try await self.transition(on: true)
                    return
                }
                guard self.hardware.supported else { return }
                if !desired && Date() < self.notBefore { return }
                if desired && self.snapshot.lidClosed { return }
                if self.snapshot.builtIn != nil && self.snapshot.builtInIsOn != desired {
                    try await self.transition(on: desired)
                } else if desired && self.guardExpected {
                    self.releaseGuard()
                }
            } catch {
                await self.handleFailure(error)
            }
        }
    }

    private func transition(on: Bool) async throws {
        busy = true
        defer { busy = false }
        if !on {
            try guardProcess.start()
            guardExpected = true
            hasDisabled = true // Even a failed transaction may need rollback.
        }
        try hardware.setBuiltIn(on: on)
        for _ in 0..<12 {
            try await Task.sleep(nanoseconds: 150_000_000)
            snapshot = try hardware.snapshot()
            if !on && (stopping || asleep || snapshot.externalDisplays.isEmpty) {
                throw DisplayFailure.noExternal
            }
            if snapshot.builtIn != nil && snapshot.builtInIsOn == on {
                if on { releaseGuard() }
                return
            }
        }
        throw DisplayFailure.verification
    }

    private func releaseGuard() {
        guardProcess.stop()
        guardExpected = false
        hasDisabled = false
    }

    private func handleFailure(_ error: Error) async {
        notice = error.localizedDescription
        policy.stopAfterFailure()
        // Verification failure must actively undo any partially applied disable.
        // Keep the helper alive if restoration does not complete.
        if hasDisabled {
            do { try await transition(on: true) }
            catch {
                notice = "Не удалось восстановить экран. Отсоедините внешний монитор или закройте и откройте крышку MacBook."
            }
        }
        snapshot = (try? hardware.snapshot()) ?? snapshot
    }

    private func prepareForSleep() {
        asleep = true
        if hasDisabled {
            try? hardware.setBuiltIn(on: true)
            // Closing the pipe asks the independent helper to verify recovery.
            releaseGuard()
        }
    }

    @objc private func emergencyRestore() {
        policy.stopAfterFailure()
        notice = nil
        notBefore = .distantPast
        requestEvaluation()
    }

    func stop() async -> Bool {
        stopping = true
        timer?.invalidate()
        if registeredCallback {
            CGDisplayRemoveReconfigurationCallback(displayChanged, Unmanaged.passUnretained(self).toOpaque())
        }
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        DistributedNotificationCenter.default().removeObserver(self)
        // Let an in-flight transaction finish before restoring and terminating.
        if let evaluation { await evaluation.value }
        if hasDisabled {
            do { try await transition(on: true) }
            catch { guardProcess.stop(); return false }
        }
        releaseGuard()
        return true
    }

    /// Explicit integration probe; never used during normal launch. It exercises
    /// the same guarded transaction and verification path as the menu switch.
    func hardwareTest() async throws {
        snapshot = try hardware.snapshot()
        guard !snapshot.lidClosed else { throw DisplayFailure.lidClosed }
        guard snapshot.builtInIsOn, snapshot.canDisable else { throw DisplayFailure.noExternal }
        do {
            try await transition(on: false)
            print("PASS: built-in display is offline; external display remains active")
            try await Task.sleep(nanoseconds: 2_000_000_000)
            try await transition(on: true)
            print("PASS: built-in display restored and online")
        } catch {
            _ = hardware.recover()
            guardProcess.stop()
            throw error
        }
    }
}

private let displayChanged: CGDisplayReconfigurationCallBack = { _, flags, context in
    guard !flags.contains(.beginConfigurationFlag), let context else { return }
    let controller = Unmanaged<DisplayController>.fromOpaque(context).takeUnretainedValue()
    Task { @MainActor in controller.displaysChanged() }
}
