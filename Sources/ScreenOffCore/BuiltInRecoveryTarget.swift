import Foundation

/// WindowServer may stop enumerating a software-disabled built-in after the
/// last external is unplugged, yet still accept an enable for its previous ID.
/// Remember only IDs actually identified as built-in during this process.
struct BuiltInRecoveryTarget {
    private(set) var lastKnownID: UInt32?

    mutating func observe(_ snapshot: DisplaySnapshot) {
        if let panel = snapshot.builtIn { lastKnownID = panel.id }
    }

    func resolve(in snapshot: DisplaySnapshot, on: Bool, recovery: Bool) -> UInt32? {
        // Always prefer a current, positively identified panel (IDs can change).
        if let panel = snapshot.builtIn { return panel.id }
        // A remembered ID is exclusively an emergency ENABLE target. Never
        // use it to disable, with the lid closed, or with a usable external.
        guard on, recovery, !snapshot.lidClosed, snapshot.externalDisplays.isEmpty,
              let lastKnownID,
              !snapshot.displays.contains(where: { $0.id == lastKnownID }) else { return nil }
        return lastKnownID
    }
}

enum DisplayHardwareIdentity {
    static func isUsableExternal(vendor: UInt32, model: UInt32) -> Bool {
        guard vendor != 0, model != 0 else { return false }
        // Observed WindowServer headless placeholder: ASCII "unkn" / "virt".
        // It has nonzero identifiers but is not a connected physical monitor.
        return !(vendor == 0x756E6B6E && model == 0x76697274)
    }
}
