import Foundation

/// Durable rescue state, independent of every synchronous WindowServer call.
/// A timeout stops automatic retries until a real wake/lid/topology change.
@MainActor
final class WatchdogSupervisor {
    private let worker: any DisplayTransactionRunning
    private let clock: () -> TimeInterval
    private let restored: () -> Void
    private(set) var snapshot: DisplaySnapshot
    private var seed: DisplayInfo?
    private let protectedExternals: Set<String>
    private(set) var recoveryRequested = false
    private(set) var hasDisabled = false
    private(set) var generation = 0
    private(set) var retryBlocked = false
    private var retryAt: TimeInterval = -.infinity
    private var workerEnabling = false
    private var consecutiveRestored = 0
    private var lastConfirmation: TimeInterval = -.infinity
    private var lidClosed: Bool?
    private var sessionActive = true
    private var screensAwake = true
    private var systemAwake = true
    private var snapshotAfterTransaction = true
    private var awaitingVerification = false

    init(snapshot: DisplaySnapshot, worker: any DisplayTransactionRunning, seed: DisplayInfo? = nil,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         restored: @escaping () -> Void) {
        self.snapshot = snapshot
        self.seed = snapshot.builtIn ?? seed
        self.protectedExternals = snapshot.externalIdentities
        self.lidClosed = snapshot.lidClosed
        self.worker = worker
        self.clock = clock
        self.restored = restored
    }

    func requestDisable() {
        guard !hasDisabled, !recoveryRequested, !worker.isRunning,
              lidClosed == false, sessionActive, screensAwake, systemAwake,
              snapshot.builtInIsRestored, snapshot.canDisable else {
            requestRestore()
            return
        }
        hasDisabled = true // A failed or cancelled call may partially apply.
        launch(on: false)
    }

    func requestRestore() {
        recoveryRequested = true
        if worker.isRunning && !workerEnabling { worker.cancel() }
    }

    func sessionChanged(active: Bool) {
        guard sessionActive != active else { return }
        sessionActive = active
        if active {
            systemAwake = true
            screensAwake = true
            allowRetry()
        } else { requestRestore() }
    }

    func screensChanged(awake: Bool) {
        guard screensAwake != awake else { return }
        screensAwake = awake
        if awake { systemAwake = true; allowRetry() }
        else { suspend() }
    }

    func systemChanged(awake: Bool) {
        guard systemAwake != awake else { return }
        systemAwake = awake
        if awake { screensAwake = true; allowRetry() }
        else { suspend() }
    }

    func lidChanged(closed: Bool?) {
        guard lidClosed != closed else { return }
        lidClosed = closed
        if closed == false {
            // Opening the physical lid is an independent wake indication even
            // when AppKit failed to deliver sleep/wake notifications.
            systemAwake = true
            screensAwake = true
            allowRetry()
        } else { suspend() }
    }

    func externalRemoved() {
        requestRestore()
        // Repeated removal callbacks must not renew a timed-out transaction.
    }

    func observe(_ state: DisplaySnapshot?) {
        guard let state else { requestRestore(); return }
        if state.externalIdentities != snapshot.externalIdentities { allowRetry() }
        snapshot = state
        snapshotAfterTransaction = true
        awaitingVerification = false
        if let panel = state.builtIn { seed = panel }
        lidChanged(closed: state.lidClosed)
        if hasDisabled && (protectedExternals.isDisjoint(with: state.externalIdentities)
                          || (state.builtInIsOn && !worker.isRunning)) {
            requestRestore()
        }
        if recoveryRequested && !worker.isRunning && state.builtInIsRestored {
            if clock() - lastConfirmation >= 0.4 {
                consecutiveRestored += 1
                lastConfirmation = clock()
            }
            if consecutiveRestored >= 2 { restored() }
        } else { consecutiveRestored = 0 }
    }

    func tick() {
        guard recoveryRequested, !worker.isRunning, lidClosed == false,
              screensAwake, systemAwake, !retryBlocked, !awaitingVerification, clock() >= retryAt,
              !(snapshotAfterTransaction && snapshot.builtInIsRestored) else { return }
        launch(on: true)
    }

    private func suspend() {
        requestRestore()
        // Sleep can interrupt an enable too. Stop only the disposable worker;
        // this supervisor and its remembered target survive until actual wake.
        if worker.isRunning { worker.cancel() }
    }

    private func allowRetry() {
        retryBlocked = false
        awaitingVerification = false
        retryAt = clock() + 0.5
    }

    private func launch(on: Bool) {
        workerEnabling = on
        snapshotAfterTransaction = false
        generation += 1
        do {
            try worker.start(DisplayTransactionRequest(on: on, lastKnownBuiltIn: seed)) { [weak self] result in
                guard let self else { return }
                self.generation += 1
                self.retryAt = self.clock() + (result == .cancelled || !on && result == .completed ? 0 : 2)
                self.awaitingVerification = on && result == .completed
                if result == .timedOut || result == .deferred {
                    self.retryBlocked = true
                }
                if result != .completed || !on && self.recoveryRequested {
                    self.requestRestore()
                }
            }
        } catch {
            requestRestore()
            retryBlocked = true
        }
    }
}
