import Foundation

/// Fail-safe conditions for the independent recovery lease.
enum WatchdogRules {
    static let heartbeatTimeout: TimeInterval = 8
    static func shouldRecover(parentAlive: Bool, pipeOpen: Bool,
                              heartbeatAge: TimeInterval, externalCount: Int, lidClosed: Bool = false) -> Bool {
        !parentAlive || !pipeOpen || heartbeatAge > heartbeatTimeout || externalCount == 0 || lidClosed
    }
}

/// Heartbeats pause during actual system sleep. A genuine wake grants one
/// fresh lease; duplicate wake callbacks cannot keep an unresponsive parent alive.
struct WatchdogHeartbeat {
    private(set) var receivedAt: TimeInterval
    private(set) var systemAwake = true
    init(now: TimeInterval) { receivedAt = now }
    mutating func receive(now: TimeInterval) { receivedAt = now }
    mutating func systemChanged(awake: Bool, now: TimeInterval) {
        guard systemAwake != awake else { return }
        systemAwake = awake
        if awake { receivedAt = now }
    }
    func expired(now: TimeInterval) -> Bool {
        systemAwake && now - receivedAt > WatchdogRules.heartbeatTimeout
    }
}
