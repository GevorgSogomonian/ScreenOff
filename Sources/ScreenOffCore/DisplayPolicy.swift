import Foundation

struct DisplayInfo: Codable, Equatable {
    let id: UInt32
    let identity: String
    let builtIn: Bool
    let online: Bool
    let active: Bool
    let mirrored: Bool
    var hasHardwareIdentity: Bool = true
}

struct DisplaySnapshot: Codable, Equatable {
    var displays: [DisplayInfo]
    var lidClosed: Bool

    var builtIn: DisplayInfo? { displays.first { $0.builtIn } }
    var builtInIsOn: Bool { builtIn?.online == true }
    var builtInIsRestored: Bool { !lidClosed && builtIn?.online == true && builtIn?.active == true }
    var externalDisplays: [DisplayInfo] {
        displays.filter { !$0.builtIn && $0.online && $0.active && $0.hasHardwareIdentity }
    }
    var externalIdentities: Set<String> { Set(externalDisplays.map(\.identity)) }
    var canDisable: Bool {
        builtIn != nil && !lidClosed && !externalDisplays.isEmpty
            && !displays.contains { $0.online && $0.mirrored }
    }
}

/// Manual choice lasts until the external-monitor topology changes. Our own
/// built-in display reconfiguration must never erase that choice.
struct DisplayPolicy {
    private(set) var automatic: Bool
    private(set) var manualOn: Bool?
    private var previousExternals: Set<String>?
    private(set) var inhibited = false

    init(automatic: Bool = false) { self.automatic = automatic }

    mutating func setAutomatic(_ enabled: Bool) {
        automatic = enabled
        manualOn = nil
        inhibited = false
    }

    mutating func setManual(on: Bool) {
        manualOn = on
        inhibited = false
    }

    mutating func stopAfterFailure() {
        inhibited = true
        manualOn = true
    }

    mutating func wantsBuiltInOn(for snapshot: DisplaySnapshot) -> Bool {
        let current = snapshot.externalIdentities
        if let previousExternals, previousExternals != current {
            manualOn = nil
            inhibited = false
        }
        previousExternals = current
        guard !current.isEmpty else {
            manualOn = nil
            return true
        }
        guard !inhibited, snapshot.canDisable else { return true }
        return manualOn ?? !automatic
    }
}

enum DisplayFailure: LocalizedError {
    case unavailable(String)
    case system(String, Int32)
    case noBuiltIn
    case noExternal
    case lidClosed
    case mirroring
    case verification
    case watchdog
    case sessionInactive
    case displaysAsleep

    var errorDescription: String? {
        switch self {
        case .unavailable(let symbol):
            return "This version of macOS does not provide \(symbol). Display disabling is unavailable."
        case .system(let operation, let code):
            return "macOS could not complete \(operation) (code \(code))."
        case .noBuiltIn: return "The built-in display is unavailable. Open your MacBook lid."
        case .noExternal: return "Connect and turn on an external monitor first."
        case .lidClosed: return "Open your MacBook lid to control the built-in display."
        case .mirroring: return "Turn off mirroring in macOS Display settings, then try again."
        case .verification: return "macOS did not confirm the display change. Automatic disabling is paused until the monitor reconnects."
        case .watchdog: return "Display recovery protection is unavailable. The built-in display has been left on."
        case .sessionInactive: return "Display disabling is paused while your Mac is locked."
        case .displaysAsleep: return "Display recovery will continue when your displays wake."
        }
    }
}
