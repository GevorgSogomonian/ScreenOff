import Foundation
import CoreGraphics
import IOKit
import Darwin

enum DisplayEnvironment {
    /// This path does not contact WindowServer and remains usable when a
    /// display query or transaction is stuck in another thread/process.
    static func lidClosed() -> Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        return IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString,
                                              kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
    }

    /// A locked console still belongs to this user. Another user's console or
    /// an unknown session cannot authorize disabling a display.
    static func sessionAvailable() -> Bool? {
        guard let state = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
        return sessionAvailable(state, owner: getuid())
    }

    static func sessionAvailable(_ state: [String: Any], owner: uid_t) -> Bool {
        guard let user = state[kCGSessionUserIDKey as String] as? NSNumber,
              user.uint32Value == owner,
              state[kCGSessionOnConsoleKey as String] as? Bool == true else { return false }
        return true
    }

    static func sessionActive() -> Bool? {
        guard let state = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
        return sessionAvailable(state, owner: getuid())
            && !(state["CGSSessionScreenIsLocked"] as? Bool ?? false)
    }
}
