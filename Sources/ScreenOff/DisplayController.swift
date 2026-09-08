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
    let hardware: any DisplayHardwareAccess
    private let guardProcess: any RecoveryGuarding
    private let verificationDelay: UInt64
    private var policy: DisplayPolicy
    private let preferences: UserDefaults
    private let testing: Bool
    private let previewOnly: Bool
    private var recoveryAttempts: RecoveryAttemptGate
    private let recoveryClock: () -> TimeInterval
    private var timer: Timer?
    private var evaluation: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var asleep = false
    private var stopping = false
    private var notBefore = Date.distantPast
    private var hasDisabled = false
    private var recoveryRequested = false
    private var protectedExternalIdentities: Set<String> = []
    private var protectedExternalIDs: Set<UInt32> = []
    private var registeredCallback = false
    static let recoverNotification = Notification.Name("com.gevorg.screenoff.restore")

    init(preferences: UserDefaults = .standard, testing: Bool = false,
         hardware: any DisplayHardwareAccess = DisplayHardware(),
         guardProcess: (any RecoveryGuarding)? = nil,
         automaticPreference: Bool? = nil, verificationDelay: UInt64 = 150_000_000,
         previewOnly: Bool = false, recoveryRetryDelay: TimeInterval = 2,
         recoveryClock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.hardware = hardware
        self.guardProcess = guardProcess ?? RecoveryGuard()
        self.verificationDelay = verificationDelay
        self.preferences = preferences
        self.testing = testing
        self.previewOnly = previewOnly
        self.recoveryAttempts = RecoveryAttemptGate(retryDelay: recoveryRetryDelay)
        self.recoveryClock = recoveryClock
        let saved = automaticPreference ?? (!testing && preferences.bool(forKey: "automaticDisplayOff"))
        policy = DisplayPolicy(automatic: saved)
        automatic = saved
        if !hardware.supported {
            notice = DisplayFailure.unavailable("API отключения дисплея").localizedDescription
        }
        snapshot = (try? hardware.snapshot()) ?? snapshot
    }

    var canToggle: Bool {
        hardware.supported && !busy && !recoveryRequested && !snapshot.lidClosed && snapshot.builtIn != nil
            && (!snapshot.builtInIsOn || snapshot.canDisable)
    }

    /// Preserve the existing saved preference, with a positive UI meaning:
    /// ON = use both displays; OFF = automatically disable the built-in.
    var usesBuiltInWithExternal: Bool { !automatic }

    func setUsesBuiltInWithExternal(_ enabled: Bool) {
        setAutomatic(!enabled)
    }

    var statusText: String {
        if let notice { return notice }
        if busy { return "Переключение дисплея…" }
        if snapshot.lidClosed { return "Крышка MacBook закрыта" }
        if snapshot.builtIn == nil { return "Встроенный дисплей не найден" }
        if snapshot.displays.contains(where: { $0.online && $0.mirrored }) {
            return "Для отключения экрана выключите видеоповтор в macOS"
        }
        if snapshot.externalDisplays.isEmpty { return "Без внешнего монитора экран MacBook включён" }
        return snapshot.builtInIsOn ? "Встроенный дисплей включён" : "Работает только внешний дисплей"
    }

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        registeredCallback = CGDisplayRegisterReconfigurationCallback(displayChanged, context) == .success
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.requestEvaluation() }
        }
        timer.tolerance = 0.5
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

    func displaysChanged(displayID: UInt32? = nil, flags: CGDisplayChangeSummaryFlags = []) {
        if let displayID, hasDisabled, protectedExternalIDs.contains(displayID),
           !flags.intersection([.removeFlag, .disabledFlag]).isEmpty {
            // An explicit removal wins even if CoreGraphics still exposes an
            // old active list or creates a temporary headless virtual display.
            recoveryRequested = true
            guardProcess.requestRestore()
        }
        // Let link training and WindowServer reconfiguration settle. The helper
        // independently restores immediately if the last external disappears.
        notBefore = max(notBefore, Date().addingTimeInterval(0.8))
        requestEvaluation()
    }

    func setBuiltIn(on: Bool) {
        guard !busy, !recoveryRequested || on else { return }
        policy.setManual(on: on)
        notice = nil
        notBefore = .distantPast
        requestEvaluation()
    }

    func setAutomatic(_ enabled: Bool) {
        policy.setAutomatic(enabled)
        automatic = enabled
        if !testing { preferences.set(enabled, forKey: "automaticDisplayOff") }
        notice = nil
        // Login registration follows the mode that requires background work.
        // Preview/test instances never register login items or save preferences.
        if testing {
            notBefore = .distantPast
            requestEvaluation()
            return
        }
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
        guard automatic, !testing else { loginNotice = nil; return }
        switch SMAppService.mainApp.status {
        case .enabled: loginNotice = nil
        case .requiresApproval:
            loginNotice = "Разрешите ScreenOff в Системных настройках → Основные → Объекты входа."
        default:
            loginNotice = "Для работы после перезагрузки добавьте ScreenOff в Объекты входа macOS."
        }
    }

    func requestEvaluation() {
        guard !previewOnly, !stopping, evaluation == nil else { return }
        evaluation = Task { [weak self] in
            guard let self else { return }
            defer { self.evaluation = nil }
            do {
                self.updateSnapshot(try self.hardware.snapshot())
                let desired = self.policy.wantsBuiltInOn(for: self.snapshot)
                if !self.hasDisabled && self.snapshot.builtIn != nil &&
                    !self.snapshot.builtInIsOn && !self.snapshot.lidClosed {
                    // A previous process or a sleep transition may have left
                    // the panel off. Adopt recovery responsibility immediately.
                    self.hasDisabled = true
                    self.recoveryRequested = true
                    self.policy.stopAfterFailure()
                }
                guard self.hardware.supported else { return }
                if self.hasDisabled {
                    if desired || self.asleep || self.snapshot.lidClosed || self.snapshot.builtIn == nil ||
                        self.snapshot.builtInIsOn ||
                        self.protectedExternalIdentities.isDisjoint(with: self.snapshot.externalIdentities) {
                        self.recoveryRequested = true
                    }
                    if !self.guardProcess.isRunning {
                        self.recoveryRequested = true
                        self.policy.stopAfterFailure()
                        try self.guardProcess.start(restoring: true)
                    }
                }
                if self.recoveryRequested {
                    self.policy.stopAfterFailure()
                    self.guardProcess.requestRestore()
                    if self.snapshot.builtInIsRestored {
                        self.releaseGuard()
                        return
                    }
                    guard self.recoveryAttempts.shouldAttempt(in: self.snapshot, now: self.recoveryClock()) else {
                        self.showRecoveryNotice()
                        return
                    }
                    if self.snapshot.lidClosed {
                        // One best-effort clear, then wait without verification
                        // polling or animation. Keep the helper until lid-open.
                        try? self.hardware.setBuiltIn(on: true, recovery: true)
                        self.showRecoveryNotice()
                        return
                    }
                    try await self.transition(on: true)
                    return
                }
                guard !self.asleep, Date() >= self.notBefore else { return }
                if !desired && self.snapshot.builtInIsOn {
                    try await self.transition(on: false)
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
            try guardProcess.start(restoring: false)
            hasDisabled = true // Even a failed transaction may need rollback.
            protectedExternalIdentities = snapshot.externalIdentities
            protectedExternalIDs = Set(snapshot.externalDisplays.map(\.id))
        }
        try hardware.setBuiltIn(on: on, recovery: on)
        for _ in 0..<12 {
            try await Task.sleep(nanoseconds: verificationDelay)
            updateSnapshot(try hardware.snapshot())
            if on && snapshot.lidClosed {
                recoveryAttempts.waitForOpenLid()
                recoveryRequested = true
                guardProcess.requestRestore()
                showRecoveryNotice()
                throw DisplayFailure.lidClosed
            }
            if !on && (stopping || asleep || recoveryRequested || snapshot.lidClosed || snapshot.externalDisplays.isEmpty) {
                throw DisplayFailure.noExternal
            }
            if on ? snapshot.builtInIsRestored : (snapshot.builtIn != nil && !snapshot.builtInIsOn) {
                if on { releaseGuard() }
                return
            }
        }
        throw DisplayFailure.verification
    }

    private func releaseGuard() {
        guard snapshot.builtInIsRestored else { return }
        guardProcess.stop()
        hasDisabled = false
        recoveryRequested = false
        recoveryAttempts.reset()
        protectedExternalIdentities = []
        protectedExternalIDs = []
        notBefore = max(notBefore, Date().addingTimeInterval(2))
        updateNotice(nil)
    }

    private func updateSnapshot(_ value: DisplaySnapshot) {
        if snapshot != value { snapshot = value }
    }

    private func updateNotice(_ value: String?) {
        if notice != value { notice = value }
    }

    private func showRecoveryNotice() {
        updateNotice(snapshot.lidClosed
            ? "Восстановление экрана продолжится после открытия крышки."
            : "Восстанавливаю встроенный экран…")
    }

    private func handleFailure(_ error: Error) async {
        policy.stopAfterFailure()
        // Verification failure must actively undo any partially applied disable.
        // Keep the helper alive if restoration does not complete.
        if hasDisabled {
            recoveryRequested = true
            guardProcess.requestRestore()
            if let state = try? hardware.snapshot() { updateSnapshot(state) }
            // Roll back a failed disable immediately, but never issue a second
            // enable after a failed recovery in the same evaluation.
            if recoveryAttempts.shouldAttempt(in: snapshot, now: recoveryClock()) {
                try? hardware.setBuiltIn(on: true, recovery: true)
            }
            showRecoveryNotice()
        } else {
            updateNotice(error.localizedDescription)
        }
        if let state = try? hardware.snapshot() { updateSnapshot(state) }
    }

    private func prepareForSleep() {
        asleep = true
        if hasDisabled {
            recoveryRequested = true
            guardProcess.requestRestore()
            if let state = try? hardware.snapshot() { updateSnapshot(state) }
            if recoveryAttempts.shouldAttempt(in: snapshot, now: recoveryClock()) {
                try? hardware.setBuiltIn(on: true, recovery: true)
            }
            // Keep the helper and obligation through sleep/lid closure.
        }
    }

    @objc private func emergencyRestore() {
        policy.stopAfterFailure()
        asleep = false
        if hasDisabled { recoveryRequested = true }
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
            recoveryRequested = true
            guardProcess.requestRestore()
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

private let displayChanged: CGDisplayReconfigurationCallBack = { displayID, flags, context in
    guard !flags.contains(.beginConfigurationFlag), let context else { return }
    let controller = Unmanaged<DisplayController>.fromOpaque(context).takeUnretainedValue()
    Task { @MainActor in controller.displaysChanged(displayID: displayID, flags: flags) }
}

#if CONTROLLER_TEST
extension DisplayController {
    func testEvaluate() async {
        requestEvaluation()
        if let evaluation { await evaluation.value }
    }
    func testSleep() { prepareForSleep() }
    var testRecoveryPending: Bool { hasDisabled }
    var testRecoveryRequested: Bool { recoveryRequested }
}
#endif
