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
    private var recoveryTarget = BuiltInRecoveryTarget()
    let resolvedSymbol: String?

    init(recoverySeed: DisplayInfo? = nil) {
        if let seed = recoverySeed, seed.builtIn, seed.id != 0 {
            recoveryTarget.observe(DisplaySnapshot(displays: [seed], lidClosed: false))
        }
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
            guard error == .success else { throw DisplayFailure.system("display enumeration", error.rawValue) }
            if count < capacity {
                ids = Array(buffer.prefix(Int(count)))
                break
            }
            guard capacity < 4096 else { throw DisplayFailure.system("display enumeration: too many displays", -1) }
            capacity *= 2
        }
        func publicIDs(_ query: (UInt32, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?) -> CGError) throws -> Set<UInt32> {
            var capacity: UInt32 = 16
            while capacity <= 4096 {
                var buffer = [UInt32](repeating: 0, count: Int(capacity))
                var count: UInt32 = 0
                let error = query(capacity, &buffer, &count)
                guard error == .success else { throw DisplayFailure.system("display status lookup", error.rawValue) }
                if count < capacity { return Set(buffer.prefix(Int(count))) }
                capacity *= 2
            }
            throw DisplayFailure.system("display enumeration: too many displays", -1)
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
                               hasHardwareIdentity: DisplayHardwareIdentity.isUsableExternal(
                                vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id)))
        }
        let result = DisplaySnapshot(displays: displays, lidClosed: DisplayEnvironment.lidClosed() ?? true)
        recoveryTarget.observe(result)
        return result
    }

    /// Prefer the current built-in ID. When unplugging leaves only a headless
    /// placeholder and hides the panel entirely, enable its last verified ID.
    /// This fallback is never allowed for disabling a display.
    func setBuiltIn(on: Bool, recovery: Bool = false) throws {
        guard let enable, list != nil else {
            throw DisplayFailure.unavailable("SLSConfigureDisplayEnabled / SLSGetDisplayList")
        }
        let current = try snapshot()
        // Do not contend with macOS clamshell reconfiguration. Recovery must
        // wait for the lid to open, including explicit CLI recovery requests.
        guard !current.lidClosed else { throw DisplayFailure.lidClosed }
        guard let targetID = recoveryTarget.resolve(in: current, on: on, recovery: recovery)
        else { throw DisplayFailure.noBuiltIn }
        // Online alone is insufficient during recovery (closed lid/inactive
        // panel). But re-enabling an already active panel can be rejected by
        // SkyLight as a redundant transaction. Callers verify after yielding.
        if current.builtIn?.online == on && (!recovery || current.builtInIsRestored) { return }
        if !on {
            guard DisplayEnvironment.sessionActive() == true else { throw DisplayFailure.sessionInactive }
            guard !current.lidClosed else { throw DisplayFailure.lidClosed }
            guard !current.externalDisplays.isEmpty else { throw DisplayFailure.noExternal }
            guard !current.displays.contains(where: { $0.online && $0.mirrored }) else { throw DisplayFailure.mirroring }
        }
        // The lid may have closed while obtaining the display configuration.
        guard DisplayEnvironment.lidClosed() == false else { throw DisplayFailure.lidClosed }
        // A physical screen can sleep without the computer sleeping. Do not
        // start a transaction while WindowServer is powering down its displays.
        let online = current.displays.filter(\.online)
        if !online.isEmpty && online.allSatisfy({ CGDisplayIsAsleep($0.id) != 0 }) {
            throw DisplayFailure.displaysAsleep
        }
        var configuration: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&configuration)
        guard begin == .success, let configuration else {
            throw DisplayFailure.system("starting the display change", begin.rawValue)
        }
        let configured = enable(configuration, targetID, on)
        guard configured == .success else {
            CGCancelDisplayConfiguration(configuration)
            throw DisplayFailure.system("changing the display state", configured.rawValue)
        }
        // No persistent configuration. Emergency recovery writes an enabled
        // session state so it survives the watchdog's own exit.
        let commit = CGCompleteDisplayConfiguration(configuration, recovery ? .forSession : .forAppOnly)
        guard commit == .success else {
            throw DisplayFailure.system("applying the display change", commit.rawValue)
        }
    }

}
