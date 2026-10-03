import Foundation
import CoreGraphics

@main
enum SessionPolicyTests {
    static var checks = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard value() else { fatalError("FAIL: \(message)") }
    }
    static func main() {
        let owner: UInt32 = 501
        let uid = kCGSessionUserIDKey as String
        let console = kCGSessionOnConsoleKey as String
        for locked in [false, true] {
            expect(DisplayEnvironment.sessionAvailable([uid: owner, console: true,
                "CGSSessionScreenIsLocked": locked], owner: owner), "own console remains available with lock=\(locked)")
            expect(!DisplayEnvironment.sessionAvailable([uid: 502, console: true,
                "CGSSessionScreenIsLocked": locked], owner: owner), "another user's console cannot authorize disabling")
            expect(!DisplayEnvironment.sessionAvailable([uid: owner, console: false,
                "CGSSessionScreenIsLocked": locked], owner: owner), "off-console session is unavailable")
        }
        expect(!DisplayEnvironment.sessionAvailable([:], owner: owner), "missing session fails closed")
        expect(!DisplayEnvironment.sessionAvailable([uid: owner], owner: owner), "missing console flag fails closed")
        expect(!DisplayEnvironment.sessionAvailable([console: true], owner: owner), "missing owner fails closed")
        var lease = WatchdogHeartbeat(now: 0)
        expect(!lease.expired(now: 8), "heartbeat deadline remains eight seconds")
        expect(lease.expired(now: 9), "awake unresponsive parent still loses lease")
        lease.systemChanged(awake: false, now: 10)
        expect(!lease.expired(now: 28_810), "eight-hour sleep does not falsely expire heartbeat")
        lease.systemChanged(awake: true, now: 28_810)
        expect(!lease.expired(now: 28_818), "real wake permits fresh parent heartbeat")
        lease.systemChanged(awake: true, now: 28_820)
        expect(lease.expired(now: 28_820), "duplicate wake cannot hide a dead heartbeat")
        lease.receive(now: 28_820)
        expect(!lease.expired(now: 28_828), "fresh heartbeat renews ordinary lease")
        print("PASS: \(checks) console ownership, lock and sleep heartbeat checks")
    }
}
