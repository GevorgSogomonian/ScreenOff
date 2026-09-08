import Foundation

/// One opportunity to reapply the saved mode after a real inactive -> active
/// cycle. Duplicate wake/unlock notifications never grant additional retries.
struct SessionResumeState {
    private(set) var sessionActive = true
    private(set) var screensAwake = true
    private(set) var systemAwake = true
    private(set) var pending = false
    private var readyAt: TimeInterval?

    var suspended: Bool { !sessionActive || !screensAwake || !systemAwake }

    mutating func setSessionActive(_ active: Bool, now: TimeInterval) {
        guard sessionActive != active else { return }
        sessionActive = active
        if active { systemAwake = true; screensAwake = true }
        changed(now: now)
    }

    mutating func setScreensAwake(_ awake: Bool, now: TimeInterval) {
        guard screensAwake != awake else { return }
        screensAwake = awake
        if awake { systemAwake = true }
        changed(now: now)
    }

    mutating func setSystemAwake(_ awake: Bool, now: TimeInterval) {
        guard systemAwake != awake else { return }
        systemAwake = awake
        changed(now: now)
    }

    private mutating func changed(now: TimeInterval) {
        if suspended {
            pending = true
            readyAt = nil
        } else if pending {
            readyAt = now + 2
        }
    }

    func ready(now: TimeInterval) -> Bool {
        pending && !suspended && readyAt.map { now >= $0 } == true
    }

    mutating func consume() { pending = false; readyAt = nil }
}
