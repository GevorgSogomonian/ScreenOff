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

    var errorDescription: String? {
        switch self {
        case .unavailable(let symbol):
            return "Эта версия macOS не предоставляет \(symbol). Отключение экрана недоступно."
        case .system(let operation, let code):
            return "macOS не выполнила действие «\(operation)» (код \(code))."
        case .noBuiltIn: return "Встроенный дисплей сейчас недоступен. Откройте крышку MacBook."
        case .noExternal: return "Сначала подключите и включите внешний монитор."
        case .lidClosed: return "Откройте крышку MacBook, чтобы управлять встроенным дисплеем."
        case .mirroring: return "Выключите видеоповтор в настройках дисплеев macOS, затем повторите."
        case .verification: return "macOS не подтвердила переключение дисплея. Автовыключение приостановлено до переподключения монитора."
        case .watchdog: return "Защита восстановления экрана недоступна. Встроенный дисплей оставлен включённым."
        }
    }
}
