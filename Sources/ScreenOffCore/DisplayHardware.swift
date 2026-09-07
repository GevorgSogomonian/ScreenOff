import CoreGraphics
import ColorSync
import Foundation
import IOKit
import Darwin

/// Runtime resolution keeps unsupported macOS versions launchable. Apple does
/// not publish a display-disconnect API. No brightness or mirroring substitute.
final class DisplayHardware: DisplayHardwareAccess {
    private typealias ListFn = @convention(c) (
        UInt32, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?
    ) -> CGError
    private typealias EnableFn = @convention(c) (
        CGDisplayConfigRef?, CGDirectDisplayID, Bool
    ) -> CGError

    private let handle: UnsafeMutableRawPointer?
    private let list: ListFn?
    private let enable: EnableFn?
    let resolvedSymbol: String?

    init() {
        let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL)
        handle = library
        func symbol(_ names: [String]) -> (String, UnsafeMutableRawPointer)? {
            guard let library else { return nil }
            for name in names {
                if let address = dlsym(library, name) { return (name, address) }
            }
            return nil
        }
        let listSymbol = symbol(["SLSGetDisplayList", "CGSGetDisplayList"])
        list = listSymbol.map { unsafeBitCast($0.1, to: ListFn.self) }
        let enableSymbol = symbol(["SLSConfigureDisplayEnabled", "CGSConfigureDisplayEnabled"])
        enable = enableSymbol.map { unsafeBitCast($0.1, to: EnableFn.self) }
        resolvedSymbol = enableSymbol?.0
    }

    deinit { if let handle { dlclose(handle) } }

    var supported: Bool { list != nil && enable != nil }

    func snapshot() throws -> DisplaySnapshot {
        // Grow rather than silently truncating a topology. The private list
        // includes disconnected panels that CGGetOnlineDisplayList omits.
        var capacity: UInt32 = 16
        var ids: [UInt32] = []
        while true {
            var buffer = [UInt32](repeating: 0, count: Int(capacity))
            var count: UInt32 = 0
            let error: CGError
            if let list { error = list(capacity, &buffer, &count) }
            else { error = CGGetOnlineDisplayList(capacity, &buffer, &count) }
            guard error == .success else { throw DisplayFailure.system("список дисплеев", error.rawValue) }
            if count < capacity {
                ids = Array(buffer.prefix(Int(count)))
                break
            }
            guard capacity < 4096 else { throw DisplayFailure.system("слишком много дисплеев", -1) }
            capacity *= 2
        }
        func publicIDs(_ query: (UInt32, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?) -> CGError) throws -> Set<UInt32> {
            var capacity: UInt32 = 16
            while capacity <= 4096 {
                var buffer = [UInt32](repeating: 0, count: Int(capacity))
                var count: UInt32 = 0
                let error = query(capacity, &buffer, &count)
                guard error == .success else { throw DisplayFailure.system("состояние дисплеев", error.rawValue) }
                if count < capacity { return Set(buffer.prefix(Int(count))) }
                capacity *= 2
            }
            throw DisplayFailure.system("слишком много дисплеев", -1)
        }
        let online = try publicIDs(CGGetOnlineDisplayList)
        let active = try publicIDs(CGGetActiveDisplayList)
        let displays = ids.filter { id in
            online.contains(id) || CGDisplayVendorNumber(id) != 0 || CGDisplayModelNumber(id) != 0
        }.map { id in
            let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue()
            let identity = uuid.map { CFUUIDCreateString(kCFAllocatorDefault, $0) as String }
                ?? "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(id)"
            return DisplayInfo(id: id, identity: identity,
                               builtIn: CGDisplayIsBuiltin(id) != 0,
                               online: online.contains(id),
                               active: active.contains(id),
                               mirrored: CGDisplayIsInMirrorSet(id) != 0,
                               hasHardwareIdentity: CGDisplayVendorNumber(id) != 0 && CGDisplayModelNumber(id) != 0)
        }
        return DisplaySnapshot(displays: displays, lidClosed: isLidClosed())
    }

    private func isLidClosed() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        return (IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString,
                                               kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool) ?? false
    }

    /// Re-resolve the built-in display before EVERY transaction, including
    /// recovery. Display IDs can change after sleep or cable reconnection.
    func setBuiltIn(on: Bool, recovery: Bool = false) throws {
        guard let enable, list != nil else {
            throw DisplayFailure.unavailable("SLSConfigureDisplayEnabled / SLSGetDisplayList")
        }
        let current = try snapshot()
        guard let target = current.builtIn else { throw DisplayFailure.noBuiltIn }
        // Online alone is insufficient during recovery (closed lid/inactive
        // panel). But re-enabling an already active panel can be rejected by
        // SkyLight as a redundant transaction. Callers verify after yielding.
        if target.online == on && (!recovery || current.builtInIsRestored) { return }
        if !on {
            guard !current.lidClosed else { throw DisplayFailure.lidClosed }
            guard !current.externalDisplays.isEmpty else { throw DisplayFailure.noExternal }
            guard !current.displays.contains(where: { $0.online && $0.mirrored }) else { throw DisplayFailure.mirroring }
        }
        var configuration: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&configuration)
        guard begin == .success, let configuration else {
            throw DisplayFailure.system("начало переключения", begin.rawValue)
        }
        let configured = enable(configuration, target.id, on)
        guard configured == .success else {
            CGCancelDisplayConfiguration(configuration)
            throw DisplayFailure.system("переключение дисплея", configured.rawValue)
        }
        // No persistent configuration. Emergency recovery writes an enabled
        // session state so it survives the watchdog's own exit.
        let commit = CGCompleteDisplayConfiguration(configuration, recovery ? .forSession : .forAppOnly)
        guard commit == .success else {
            throw DisplayFailure.system("применение переключения", commit.rawValue)
        }
    }

    /// Bounded explicit CLI probe. The watchdog uses persistent nonblocking
    /// WatchdogRecovery steps instead, so it never abandons a missing panel.
    /// Retrying obtains a fresh ID every time. Never disables any display.
    func recover() -> Bool {
        for _ in 0..<8 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            try? setBuiltIn(on: true, recovery: true)
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            if let state = try? snapshot(), state.builtInIsRestored { return true }
        }
        return false
    }
}
