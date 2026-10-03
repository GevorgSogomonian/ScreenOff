import Foundation
import CoreFoundation
import Darwin

struct DisplayModel: Hashable, Codable, Identifiable {
    let vendor: UInt32
    let product: UInt32
    var id: String { "\(String(vendor, radix: 16))-\(String(product, radix: 16))" }
    var overridePath: String {
        "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-\(String(vendor, radix: 16))/DisplayProductID-\(String(product, radix: 16))"
    }
    var recordPath: String { "/Library/Application Support/ScreenOff/DisplayRoles/\(id).plist" }
}

struct DisplayRoleError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Pure plist edits: preserve every unrelated key, including edits made after exclusion.
enum DisplayRoleOverride {
    static func dictionary(_ data: Data) throws -> [String: Any] {
        guard let result = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw DisplayRoleError(message: "The display override is not a plist dictionary.")
        }
        return result
    }

    static func encode(_ value: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
    }

    static func excluding(_ original: [String: Any], model: DisplayModel) -> [String: Any] {
        var result = original
        if result["DisplayVendorID"] == nil { result["DisplayVendorID"] = model.vendor }
        if result["DisplayProductID"] == nil { result["DisplayProductID"] = model.product }
        result["DisplayIsTV"] = true
        return result
    }

    static func restoring(_ current: [String: Any], original: [String: Any], model: DisplayModel) throws -> [String: Any] {
        // A repeated restore after a crash is harmless. Refuse to overwrite another tool's role change.
        for dictionary in [current, original] {
            if let role = dictionary["DisplayIsTV"] {
                guard let number = role as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                    throw DisplayRoleError(message: "The existing DisplayIsTV setting is not a Boolean. It was preserved.")
                }
            }
        }
        let currentRole = current["DisplayIsTV"] as? NSNumber
        let oldRole = original["DisplayIsTV"] as? NSNumber
        guard currentRole == NSNumber(value: true) || currentRole == oldRole else {
            throw DisplayRoleError(message: "Another app changed this monitor's role. Its setting was preserved.")
        }
        var result = current
        result["DisplayIsTV"] = original["DisplayIsTV"]
        for (key, value) in [("DisplayVendorID", model.vendor), ("DisplayProductID", model.product)] {
            if original[key] == nil, (result[key] as? NSNumber)?.uint32Value == value { result.removeValue(forKey: key) }
        }
        return result
    }

    static var bootID: Int64 {
        var value = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &value, &size, nil, 0) == 0 else { return 0 }
        return Int64(value.tv_sec)
    }
}
