import Foundation

/// Recovery remains armed while the lid is closed, but an impossible active
/// panel confirmation must never drive a transaction/callback feedback loop.
struct RecoveryAttemptGate {
    let retryDelay: TimeInterval
    private var attemptedWithClosedLid = false
    private var lastState: DisplaySnapshot?
    private var nextAttempt: TimeInterval = -.infinity

    init(retryDelay: TimeInterval = 2) { self.retryDelay = retryDelay }

    mutating func shouldAttempt(in state: DisplaySnapshot, now: TimeInterval) -> Bool {
        if state.lidClosed {
            // WindowServer may still be processing the lid transition. Even
            // one synchronous enable can spin inside its configuration API
            // until the lid opens. Keep the obligation without a transaction.
            attemptedWithClosedLid = true
            return false
        } else {
            if attemptedWithClosedLid || lastState != state { nextAttempt = -.infinity }
            attemptedWithClosedLid = false
            guard now >= nextAttempt else { return false }
        }
        lastState = state
        nextAttempt = now + retryDelay
        return true
    }

    mutating func waitForOpenLid() { attemptedWithClosedLid = true }

    mutating func reset() { self = Self(retryDelay: retryDelay) }
}
