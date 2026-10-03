import Foundation
import CoreGraphics
import Darwin

/// One-shot administrator operation. No daemon, input files, arbitrary paths or shell commands.
#if !ROLE_HELPER_TEST
@main
#endif
enum RoleHelper {
    static let fm = FileManager.default

    static func validate(_ path: String, directory: Bool) throws {
        var info = stat()
        guard lstat(path, &info) == 0 else { throw DisplayRoleError(message: "Cannot inspect \(path).") }
        let kind = info.st_mode & S_IFMT
        guard kind == (directory ? S_IFDIR : S_IFREG), info.st_uid == 0,
              info.st_mode & 0o022 == 0, directory || info.st_nlink == 1 else {
            throw DisplayRoleError(message: "Unsafe ownership, permissions or link at \(path).")
        }
    }

    static func parents(_ path: String, create: Bool) throws {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        var accumulated = ""
        for part in parent.split(separator: "/") {
            accumulated += "/" + part
            var info = stat()
            if lstat(accumulated, &info) != 0 {
                guard errno == ENOENT, create else { throw DisplayRoleError(message: "Missing directory: \(accumulated)") }
                try fm.createDirectory(atPath: accumulated, withIntermediateDirectories: false,
                                       attributes: [.posixPermissions: 0o755])
            }
            try validate(accumulated, directory: true)
        }
    }

    static func read(_ path: String) throws -> [String: Any]? {
        var info = stat()
        if lstat(path, &info) != 0 {
            guard errno == ENOENT else { throw DisplayRoleError(message: "Cannot read \(path).") }
            return nil
        }
        try validate(path, directory: false)
        return try DisplayRoleOverride.dictionary(Data(contentsOf: URL(fileURLWithPath: path)))
    }

    static func write(_ value: [String: Any], path: String) throws {
        try parents(path, create: true)
        _ = try read(path)
        try DisplayRoleOverride.encode(value).write(to: URL(fileURLWithPath: path), options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
    }

    static func checkExternal(_ model: DisplayModel) throws {
        var ids = [CGDirectDisplayID](repeating: 0, count: 128)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(128, &ids, &count) == .success, count < 128 else {
            throw DisplayRoleError(message: "Cannot identify connected displays.")
        }
        let matching = ids.prefix(Int(count)).filter {
            CGDisplayVendorNumber($0) == model.vendor && CGDisplayModelNumber($0) == model.product
        }
        guard !matching.isEmpty, matching.allSatisfy({ CGDisplayIsBuiltin($0) == 0 }),
              DisplayHardwareIdentity.isUsableExternal(vendor: model.vendor, model: model.product) else {
            throw DisplayRoleError(message: "Connect this external monitor before excluding it.")
        }
    }

    static func run(_ action: String, model: DisplayModel) throws {
        if action == "exclude" { try checkExternal(model) }
        try parents(model.recordPath, create: true)
        // Serialize administrator operations across app instances.
        let lockPath = "/Library/Application Support/ScreenOff/DisplayRoles/operation.lock"
        let fd = open(lockPath, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw DisplayRoleError(message: "Cannot lock display settings.") }
        defer { close(fd) }
        try validate(lockPath, directory: false)
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw DisplayRoleError(message: "Another display settings operation is running.") }
        defer { flock(fd, LOCK_UN) }
        try parents(model.overridePath, create: true)
        let current = try read(model.overridePath) ?? [:]
        let saved = try read(model.recordPath)
        if action == "exclude" {
            _ = try DisplayRoleOverride.restoring(current, original: current, model: model)
            // Save before touching the override. Repeating a failed apply keeps the original backup.
            var record = saved ?? ["original": current, "existed": fm.fileExists(atPath: model.overridePath)]
            guard let original = record["original"] as? [String: Any] else { throw DisplayRoleError(message: "Invalid recovery record.") }
            if saved != nil, record["excluded"] as? Bool == false {
                record["original"] = current
                record["existed"] = fm.fileExists(atPath: model.overridePath)
            } else if saved != nil {
                _ = try DisplayRoleOverride.restoring(current, original: original, model: model)
            }
            record["excluded"] = true
            record["boot"] = DisplayRoleOverride.bootID
            try write(record, path: model.recordPath)
            try write(DisplayRoleOverride.excluding(current, model: model), path: model.overridePath)
        } else {
            guard var record = saved, let original = record["original"] as? [String: Any] else {
                throw DisplayRoleError(message: "No ScreenOff backup exists for this monitor.")
            }
            let result = try DisplayRoleOverride.restoring(current, original: original, model: model)
            if result.isEmpty && record["existed"] as? Bool == false {
                if fm.fileExists(atPath: model.overridePath) { try fm.removeItem(atPath: model.overridePath) }
            } else { try write(result, path: model.overridePath) }
            record["excluded"] = false
            record["boot"] = DisplayRoleOverride.bootID
            try write(record, path: model.recordPath)
        }
    }

    static func main() {
        umask(0o022)
        let args = CommandLine.arguments
        guard geteuid() == 0, args.count == 4, ["exclude", "restore"].contains(args[1]),
              let vendor = UInt32(args[2]), let product = UInt32(args[3]), vendor != 0, product != 0 else {
            fputs("Invalid administrator display-role request.\n", stderr); exit(1)
        }
        do { try run(args[1], model: DisplayModel(vendor: vendor, product: product)) }
        catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    }
}
