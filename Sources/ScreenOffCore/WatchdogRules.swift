import Foundation

/// Fail-safe conditions for the independent recovery lease.
enum WatchdogRules {
    static let heartbeatTimeout: TimeInterval = 8
    static func shouldRecover(parentAlive: Bool, pipeOpen: Bool,
                              heartbeatAge: TimeInterval, externalCount: Int, lidClosed: Bool = false) -> Bool {
        !parentAlive || !pipeOpen || heartbeatAge > heartbeatTimeout || externalCount == 0 || lidClosed
    }
}
