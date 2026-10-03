import Foundation
import Darwin

@main
enum RoleHelperTests {
    static var checks = 0
    static func rejects(_ body: () throws -> Void, _ message: String) {
        do { try body(); fatalError("FAIL: \(message)") }
        catch { checks += 1 }
    }
    static func main() throws {
        try RoleHelper.validate("/Library", directory: true)
        checks += 1
        rejects({ try RoleHelper.validate("/Library", directory: false) }, "directory used as plist")
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let file = temporary.appendingPathComponent("override")
        try Data("test".utf8).write(to: file)
        if getuid() != 0 {
            rejects({ _ = try RoleHelper.read(file.path) }, "user-owned override")
        }
        let link = temporary.appendingPathComponent("symlink")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/Library")
        rejects({ try RoleHelper.validate(link.path, directory: true) }, "symlink directory")
        rejects({ try RoleHelper.validate(link.path, directory: false) }, "symlink file")
        rejects({ try RoleHelper.parents(link.appendingPathComponent("display").path, create: false) }, "unsafe parent path")
        rejects({ try RoleHelper.checkExternal(DisplayModel(vendor: 0, product: 0)) }, "invalid external identity")
        print("PASS: \(checks) read-only helper boundary checks (no administrator changes)")
    }
}
