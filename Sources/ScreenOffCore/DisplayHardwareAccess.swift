import Foundation

protocol DisplayHardwareAccess: AnyObject {
    var supported: Bool { get }
    var resolvedSymbol: String? { get }
    func snapshot() throws -> DisplaySnapshot
    func setBuiltIn(on: Bool, recovery: Bool) throws
}

extension DisplayHardwareAccess {
    func setBuiltIn(on: Bool) throws { try setBuiltIn(on: on, recovery: false) }
}
