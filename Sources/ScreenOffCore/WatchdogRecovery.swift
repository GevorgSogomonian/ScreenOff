import Foundation

/// A durable obligation: keep retrying across unavailable panels, API errors,
/// sleep and lid closure. Only a verified, open-lid active panel completes it.
struct WatchdogRecovery {
    private(set) var requested = false
    private var consecutiveRestored = 0

    mutating func request() { requested = true }

    /// Called on the helper's live AppKit run loop. Never blocks the event loop
    /// waiting for WindowServer and never disables any display.
    mutating func step(using hardware: any DisplayHardwareAccess) -> Bool {
        guard requested else { return false }
        do {
            let snapshot = try hardware.snapshot()
            if snapshot.builtInIsRestored {
                consecutiveRestored += 1
                return consecutiveRestored >= 2
            }
            consecutiveRestored = 0
            try hardware.setBuiltIn(on: true, recovery: true)
            // Let WindowServer deliver events before checking the result.
            return false
        } catch {
            consecutiveRestored = 0
            return false
        }
    }
}
