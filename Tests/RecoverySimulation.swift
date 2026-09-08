import Foundation

/// Fake asynchronous recovery backend for controller tests. Production recovery
/// uses WatchdogSupervisor and a bounded DisplayTransaction child instead.
struct SimulatedRecovery {
    private(set) var requested = false
    private var consecutiveRestored = 0
    private var attempts: RecoveryAttemptGate

    init(retryDelay: TimeInterval = 2) { attempts = RecoveryAttemptGate(retryDelay: retryDelay) }

    mutating func request() { requested = true }

    mutating func step(using hardware: any DisplayHardwareAccess,
                       now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard requested else { return false }
        do {
            let snapshot = try hardware.snapshot()
            if snapshot.builtInIsRestored {
                consecutiveRestored += 1
                return consecutiveRestored >= 2
            }
            consecutiveRestored = 0
            guard attempts.shouldAttempt(in: snapshot, now: now) else { return false }
            try hardware.setBuiltIn(on: true, recovery: true)
            // Let WindowServer deliver events before checking the result.
            return false
        } catch {
            consecutiveRestored = 0
            return false
        }
    }
}
