import Foundation
import CoreGraphics
import IOKit

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

    static func sessionActive() -> Bool? {
        guard let state = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
        return !(state["CGSSessionScreenIsLocked"] as? Bool ?? false)
            && (state[kCGSessionOnConsoleKey as String] as? Bool ?? false)
    }
}
