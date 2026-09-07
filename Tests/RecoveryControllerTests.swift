import AppKit

/// Exercise the production controller and watchdog recovery loop with injected
/// hardware. These tests never issue a real display transaction.
final class FakeDisplayHardware: DisplayHardwareAccess {
    let supported = true
    let resolvedSymbol: String? = "fake"
    var state: DisplaySnapshot
    var readFails = false
    var enableFails = false
    var activationDelayed = false
    var simulateHeadlessRecovery = false
    var recoveryTarget = BuiltInRecoveryTarget()
    var recoveredIDs: [UInt32] = []
    var afterDisable: (() -> Void)?
    var calls: [(on: Bool, recovery: Bool)] = []

    init(_ state: DisplaySnapshot = fixture()) { self.state = state }
    func snapshot() throws -> DisplaySnapshot {
        if readFails { throw DisplayFailure.verification }
        recoveryTarget.observe(state)
        return state
    }
    func setBuiltIn(on: Bool, recovery: Bool) throws {
        calls.append((on, recovery))
        if simulateHeadlessRecovery, state.builtIn == nil,
           let id = recoveryTarget.resolve(in: state, on: on, recovery: recovery) {
            recoveredIDs.append(id)
            state.displays.removeAll { !$0.hasHardwareIdentity }
            state.displays.append(DisplayInfo(id: id, identity: "builtin", builtIn: true,
                                             online: true, active: true, mirrored: false))
            return
        }
        guard state.builtIn != nil else { throw DisplayFailure.noBuiltIn }
        if on && enableFails { throw DisplayFailure.verification }
        if !on || (!state.lidClosed && !activationDelayed) {
            state.displays = state.displays.map {
                guard $0.builtIn else { return $0 }
                return DisplayInfo(id: $0.id, identity: $0.identity, builtIn: true,
                                   online: on, active: on, mirrored: false)
            }
        }
        if !on { afterDisable?() }
    }
    func recover() -> Bool { fatalError("Controller must use the verified asynchronous path") }
}

@MainActor
final class FakeRecoveryGuard: RecoveryGuarding {
    var isRunning = false
    var starts: [Bool] = []
    var restoreRequests = 0
    var stops = 0
    var startFails = false
    func start(restoring: Bool) throws {
        if startFails { throw DisplayFailure.watchdog }
        starts.append(restoring)
        isRunning = true
    }
    func requestRestore() { restoreRequests += 1 }
    func stop() { stops += 1; isRunning = false }
}

func fixture(on: Bool = true, present: Bool = true, lid: Bool = false,
             externals: [String] = ["desk"], active: Bool? = nil,
             builtInID: UInt32 = 1) -> DisplaySnapshot {
    var displays = present ? [DisplayInfo(id: builtInID, identity: "builtin", builtIn: true,
                                         online: on, active: active ?? on, mirrored: false)] : []
    displays += externals.enumerated().map {
        DisplayInfo(id: UInt32($0.offset + 2), identity: $0.element, builtIn: false,
                    online: true, active: true, mirrored: false)
    }
    return DisplaySnapshot(displays: displays, lidClosed: lid)
}

@main
@MainActor
enum RecoveryControllerTests {
    static var checks = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String,
                       file: StaticString = #file, line: UInt = #line) {
        checks += 1
        guard value() else { fatalError("FAIL: \(message)", file: file, line: line) }
    }

    static func make(_ hardware: FakeDisplayHardware = FakeDisplayHardware(),
                     _ suppliedGuard: FakeRecoveryGuard? = nil)
        -> (DisplayController, FakeDisplayHardware, FakeRecoveryGuard) {
        let guardProcess = suppliedGuard ?? FakeRecoveryGuard()
        let controller = DisplayController(testing: true, hardware: hardware,
                                           guardProcess: guardProcess, automaticPreference: true,
                                           verificationDelay: 0)
        hardware.afterDisable = { expect(guardProcess.isRunning, "helper ready before disabling") }
        return (controller, hardware, guardProcess)
    }

    static func disabled() async -> (DisplayController, FakeDisplayHardware, FakeRecoveryGuard) {
        let (controller, hardware, guardProcess) = make()
        await controller.testEvaluate()
        expect(!hardware.state.builtInIsOn && controller.testRecoveryPending,
               "automatic off takes recovery responsibility")
        expect(guardProcess.starts == [false], "normal disable starts armed helper")
        return (controller, hardware, guardProcess)
    }

    static func main() async {
        // The only UI switch expresses a persistent positive preference, not
        // the current panel state. Old automatic=true maps to switch OFF.
        do {
            let (controller, hardware, helper) = make(FakeDisplayHardware(fixture(externals: [])))
            expect(!controller.usesBuiltInWithExternal, "existing automatic preference maps to OFF")
            controller.setUsesBuiltInWithExternal(false)
            await controller.testEvaluate()
            expect(hardware.calls.isEmpty && hardware.state.builtInIsOn,
                   "OFF without an external saves intent and keeps the only display on")
            hardware.state = fixture()
            await controller.testEvaluate()
            expect(!hardware.state.builtInIsOn && helper.isRunning,
                   "attaching an external applies the saved OFF preference")
            controller.setUsesBuiltInWithExternal(true)
            await controller.testEvaluate()
            expect(controller.usesBuiltInWithExternal && hardware.state.builtInIsRestored,
                   "ON immediately restores the panel and disables automation")
            hardware.state = fixture(externals: ["another-monitor"])
            await controller.testEvaluate()
            expect(hardware.state.builtInIsOn && hardware.calls.filter { !$0.on }.count == 1,
                   "ON survives external topology changes")
        }
        do {
            let (controller, hardware, _) = make()
            controller.setBuiltIn(on: true) // Safe update/recovery override.
            await controller.testEvaluate()
            controller.setUsesBuiltInWithExternal(false)
            await controller.testEvaluate()
            expect(!hardware.state.builtInIsOn, "explicit OFF clears a temporary recovery override")
            controller.setUsesBuiltInWithExternal(true)
            await controller.testEvaluate()
        }
        do {
            let hardware = FakeDisplayHardware()
            let helper = FakeRecoveryGuard()
            let controller = DisplayController(testing: true, hardware: hardware,
                                               guardProcess: helper, previewOnly: true)
            controller.setUsesBuiltInWithExternal(false)
            await controller.testEvaluate()
            controller.setUsesBuiltInWithExternal(true)
            await controller.testEvaluate()
            expect(hardware.calls.isEmpty && helper.starts.isEmpty,
                   "clicking preview controls never starts display transactions or a helper")
        }
        // Physical unplug can temporarily remove BOTH displays from enumeration.
        do {
            let (controller, hardware, helper) = await disabled()
            hardware.state = fixture(present: false, externals: [])
            for _ in 0..<20 { await controller.testEvaluate() }
            expect(controller.testRecoveryPending && controller.testRecoveryRequested,
                   "missing panel never cancels restoration, even after many polls")
            expect(helper.stops == 0 && helper.isRunning, "missing panel keeps helper alive")
            expect(helper.restoreRequests > 0, "controller tells helper to recover")
            hardware.state = fixture(on: false, externals: [], builtInID: 99)
            await controller.testEvaluate()
            expect(hardware.state.builtInIsRestored, "returning panel with changed ID is restored")
            expect(!controller.testRecoveryPending && helper.stops == 1,
                   "release only after actual restoration")
            expect(hardware.calls.dropFirst().allSatisfy { $0.on && $0.recovery },
                   "every recovery transaction enables with session lifetime")
        }
        do {
            let (controller, hardware, helper) = await disabled()
            hardware.state = fixture(on: false, lid: true, externals: [])
            controller.testSleep()
            await controller.testEvaluate()
            expect(controller.testRecoveryPending && helper.stops == 0,
                   "sleep and closed lid do not release helper")
            expect(!hardware.state.builtInIsRestored, "closed lid is not confirmation")
            hardware.state = fixture(on: false, externals: [])
            // Deliberately omit didWake: a missed wake callback must not block recovery.
            await controller.testEvaluate()
            expect(hardware.state.builtInIsRestored && !controller.testRecoveryPending,
                   "opening lid restores even without a wake notification")
        }
        do {
            let (controller, hardware, helper) = await disabled()
            hardware.state = fixture(on: false, externals: [])
            hardware.enableFails = true
            for _ in 0..<10 { await controller.testEvaluate() }
            expect(controller.testRecoveryPending && helper.stops == 0,
                   "API failures retain responsibility")
            // Reconnection does not cancel a recovery already in progress.
            hardware.state = fixture(on: false)
            hardware.enableFails = false
            await controller.testEvaluate()
            expect(hardware.state.builtInIsRestored, "recovery survives reconnection")
            await controller.testEvaluate()
            expect(hardware.state.builtInIsRestored, "no immediate automatic redisable after recovery")
        }
        do {
            let (controller, hardware, helper) = await disabled()
            hardware.state = fixture(on: true, externals: [], active: false)
            hardware.activationDelayed = true
            await controller.testEvaluate()
            expect(controller.testRecoveryPending && helper.stops == 0,
                   "online but inactive panel is not recovered")
            hardware.activationDelayed = false
            await controller.testEvaluate()
            expect(!controller.testRecoveryPending, "active state completes recovery")
        }
        do {
            let (controller, hardware, helper) = await disabled()
            helper.isRunning = false
            await controller.testEvaluate()
            expect(helper.starts == [false, true], "dead helper replaced in restore-only mode")
            expect(hardware.state.builtInIsRestored, "helper loss restores despite automatic off")
        }
        do {
            let (controller, hardware, helper) = make(FakeDisplayHardware(fixture(on: false)))
            await controller.testEvaluate()
            expect(helper.starts == [true], "startup with orphaned off panel starts recovery helper")
            expect(hardware.state.builtInIsRestored, "startup restores orphaned off panel")
        }
        for flag: CGDisplayChangeSummaryFlags in [.removeFlag, .disabledFlag] {
            let (controller, hardware, _) = await disabled()
            // Snapshot deliberately keeps the stale active external entry.
            controller.displaysChanged(displayID: 2, flags: flag)
            await controller.testEvaluate()
            expect(hardware.state.builtInIsRestored,
                   "explicit external removal wins over stale online display list")
        }
        do {
            let (controller, hardware, _) = await disabled()
            hardware.state = fixture(on: false, externals: ["temporary-headless"])
            await controller.testEvaluate()
            expect(hardware.state.builtInIsRestored,
                   "new placeholder does not substitute for protected external")
        }
        do {
            var state = fixture(externals: [])
            state.displays.append(DisplayInfo(id: 12, identity: "headless", builtIn: false,
                                               online: true, active: true, mirrored: false,
                                               hasHardwareIdentity: false))
            let (controller, hardware, helper) = make(FakeDisplayHardware(state))
            await controller.testEvaluate()
            expect(hardware.calls.isEmpty && helper.starts.isEmpty,
                   "headless entry cannot authorize disabling the only physical panel")
        }
        do {
            let (controller, hardware, helper) = await disabled()
            hardware.readFails = true
            await controller.testEvaluate()
            expect(controller.testRecoveryPending && helper.stops == 0,
                   "unreadable topology preserves protection")
            hardware.readFails = false
            await controller.testEvaluate()
            expect(hardware.state.builtInIsRestored, "read failure latches recovery")
        }
        do {
            let helper = FakeRecoveryGuard()
            helper.startFails = true
            let (controller, hardware, _) = make(FakeDisplayHardware(), helper)
            await controller.testEvaluate()
            expect(hardware.calls.isEmpty, "failed helper startup forbids off transaction")
        }
        do {
            let (controller, hardware, _) = make()
            hardware.afterDisable = { hardware.state = fixture(on: false, externals: []) }
            await controller.testEvaluate()
            expect(hardware.state.builtInIsRestored, "unplug during off verification triggers rollback")
            await controller.testEvaluate()
            expect(!controller.testRecoveryPending, "rollback confirmation releases obligation")
        }
        do {
            let (controller, hardware, _) = await disabled()
            hardware.state = fixture() // Helper has restored, but has not exited yet.
            await controller.testEvaluate()
            expect(hardware.calls.filter { !$0.on }.count == 1,
                   "controller cannot race helper by disabling a just-restored panel")
        }
        do {
            let (controller, hardware, helper) = await disabled()
            hardware.state = fixture(present: false, externals: [])
            let confirmed = await controller.stop()
            expect(!confirmed && helper.restoreRequests > 0 && helper.stops == 1,
                   "quit with unavailable panel hands recovery to helper via command and EOF")
        }
        testWatchdogRecovery()
        await testRecordedHotplug()
        print("PASS: \(checks) controller and persistent-recovery checks (simulated hardware only)")
    }

    static func recordedHeadlessState() -> DisplaySnapshot {
        // Exact topology shape observed during the failed physical unplug:
        // no ID 1, one active "unkn"/"virt" placeholder, offline alias ID 3.
        DisplaySnapshot(displays: [
            DisplayInfo(id: 13, identity: "placeholder", builtIn: false, online: true,
                        active: true, mirrored: false, hasHardwareIdentity:
                            DisplayHardwareIdentity.isUsableExternal(vendor: 1970170734, model: 1986622068)),
            DisplayInfo(id: 3, identity: "offline-alias", builtIn: false, online: false,
                        active: false, mirrored: false)
        ], lidClosed: false)
    }

    static func testRecordedHotplug() async {
        let headless = recordedHeadlessState()
        expect(headless.externalDisplays.isEmpty, "recorded unkn/virt placeholder is not an external monitor")
        expect(DisplayHardwareIdentity.isUsableExternal(vendor: 25001, model: 45061), "real monitor remains usable")
        expect(!DisplayHardwareIdentity.isUsableExternal(vendor: 0, model: 12), "missing vendor remains excluded")
        var locator = BuiltInRecoveryTarget()
        expect(locator.resolve(in: headless, on: true, recovery: true) == nil, "never invent a built-in ID")
        locator.observe(fixture())
        locator.observe(headless)
        expect(locator.resolve(in: headless, on: true, recovery: true) == 1,
               "remembered built-in ID survives complete removal from enumeration")
        expect(locator.resolve(in: headless, on: false, recovery: true) == nil, "remembered ID can never disable")
        expect(locator.resolve(in: headless, on: true, recovery: false) == nil, "fallback is recovery-only")
        var closed = headless
        closed.lidClosed = true
        expect(locator.resolve(in: closed, on: true, recovery: true) == nil, "do not force a hidden panel with closed lid")
        expect(locator.resolve(in: fixture(present: false), on: true, recovery: true) == nil,
               "do not reuse remembered ID with a physical external still active")
        var reused = headless
        reused.displays.append(DisplayInfo(id: 1, identity: "different-display", builtIn: false,
                                           online: false, active: false, mirrored: false))
        expect(locator.resolve(in: reused, on: true, recovery: true) == nil, "reject an ID now assigned to another record")
        locator.observe(fixture(builtInID: 99))
        expect(locator.resolve(in: fixture(builtInID: 99), on: true, recovery: true) == 99,
               "fresh built-in identification always wins")
        expect(locator.resolve(in: headless, on: true, recovery: true) == 99, "update remembered ID after re-enumeration")

        let (controller, hardware, helper) = await disabled()
        hardware.simulateHeadlessRecovery = true
        hardware.state = headless
        await controller.testEvaluate()
        expect(hardware.recoveredIDs == [1] && hardware.state.builtInIsRestored,
               "production controller recovers recorded unplug topology via remembered target")
        expect(!controller.testRecoveryPending && helper.stops == 1, "release after headless recovery is confirmed")

        let independent = FakeDisplayHardware()
        _ = try! independent.snapshot() // Helper handshake runs before off.
        independent.simulateHeadlessRecovery = true
        independent.state = headless
        var recovery = WatchdogRecovery()
        recovery.request()
        expect(!recovery.step(using: independent) && independent.recoveredIDs == [1],
               "independent recovery uses the same remembered target")
        expect(!recovery.step(using: independent), "headless recovery requires first active observation")
        expect(recovery.step(using: independent), "headless recovery completes on second active observation")
    }

    static func testWatchdogRecovery() {
        let hardware = FakeDisplayHardware(fixture(on: false))
        var recovery = WatchdogRecovery()
        expect(!recovery.step(using: hardware) && hardware.calls.isEmpty, "unarmed helper stays idle")
        recovery.request()
        hardware.state = fixture(present: false, externals: [])
        for _ in 0..<100 { expect(!recovery.step(using: hardware), "missing panel never completes helper") }
        hardware.state = fixture(on: true, lid: true, externals: [])
        for _ in 0..<10 { expect(!recovery.step(using: hardware), "closed lid cannot complete helper") }
        hardware.state = fixture(on: false, externals: [])
        hardware.enableFails = true
        for _ in 0..<10 { expect(!recovery.step(using: hardware), "API error cannot complete helper") }
        hardware.enableFails = false
        expect(!recovery.step(using: hardware), "enable transaction yields to event loop")
        expect(hardware.state.builtInIsRestored, "persistent helper eventually enables returning panel")
        expect(!recovery.step(using: hardware), "one successful observation is insufficient")
        hardware.readFails = true
        expect(!recovery.step(using: hardware), "transient loss resets confirmation")
        hardware.readFails = false
        expect(!recovery.step(using: hardware), "confirmation restarts after transient loss")
        expect(recovery.step(using: hardware), "two separated active observations complete helper")
        expect(hardware.calls.allSatisfy { $0.on && $0.recovery }, "helper only enables session state")
        var alreadyRestored = WatchdogRecovery()
        alreadyRestored.request()
        hardware.calls = []
        hardware.enableFails = true // SkyLight may reject redundant enables.
        expect(!alreadyRestored.step(using: hardware), "already active panel still requires confirmation")
        expect(alreadyRestored.step(using: hardware) && hardware.calls.isEmpty,
               "confirmed active panel needs no redundant enable transaction")
        expect(WatchdogRules.shouldRecover(parentAlive: true, pipeOpen: true,
                                          heartbeatAge: 0, externalCount: 1, lidClosed: true),
               "lid closure independently requests helper recovery")
    }
}
