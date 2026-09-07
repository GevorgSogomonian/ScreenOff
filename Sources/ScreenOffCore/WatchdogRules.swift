import Foundation

/// Shared with tests; the helper only ever restores, never disables.
enum WatchdogRules {
    static let heartbeatTimeout: TimeInterval = 8
    static func shouldRecover(parentAlive: Bool, pipeOpen: Bool,
                              heartbeatAge: TimeInterval, externalCount: Int) -> Bool {
        !parentAlive || !pipeOpen || heartbeatAge > heartbeatTimeout || externalCount == 0
    }
}
