import Foundation

@main
enum DisplayRoleTests {
    static var checks = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard value() else { fatalError("FAIL: \(message)") }
    }
    static func main() throws {
        let model = DisplayModel(vendor: 0x10ac, product: 0xabcd)
        expect(model.overridePath.hasSuffix("DisplayVendorID-10ac/DisplayProductID-abcd"), "canonical model path")
        for role in [nil, false, true] as [Bool?] {
            var original: [String: Any] = ["scale-resolutions": [Data([1, 2, 3])], "DisplayProductName": "Monitor"]
            if let role { original["DisplayIsTV"] = role }
            let applied = DisplayRoleOverride.excluding(original, model: model)
            expect(applied["DisplayIsTV"] as? Bool == true, "TV exclusion")
            let restored = try DisplayRoleOverride.restoring(applied, original: original, model: model)
            expect(NSDictionary(dictionary: restored).isEqual(to: original), "exact restoration of absent/false/true original role")
            let roundTrip = try DisplayRoleOverride.dictionary(DisplayRoleOverride.encode(restored))
            expect(NSDictionary(dictionary: roundTrip).isEqual(to: original), "binary and custom fields preserved through serialization")
            let retry = try DisplayRoleOverride.restoring(restored, original: original, model: model)
            expect(NSDictionary(dictionary: retry).isEqual(to: original), "restore retry after interrupted operation")
        }
        let original: [String: Any] = ["DisplayVendorID": model.vendor, "DisplayProductID": model.product, "DisplayIsTV": false]
        var current = DisplayRoleOverride.excluding(original, model: model)
        current["scale-resolutions"] = [Data([4, 5])]
        let restored = try DisplayRoleOverride.restoring(current, original: original, model: model)
        expect(restored["scale-resolutions"] as? [Data] == [Data([4, 5])], "preserves later edits by another app")
        expect(restored["DisplayVendorID"] as? UInt32 == model.vendor, "preserves pre-existing identity keys")
        let emptyApplied = DisplayRoleOverride.excluding([:], model: model)
        let emptyRestored = try DisplayRoleOverride.restoring(emptyApplied, original: [:], model: model)
        expect(emptyRestored.isEmpty, "new override can be removed completely")
        var conflict = emptyApplied
        conflict["DisplayIsTV"] = false
        do {
            _ = try DisplayRoleOverride.restoring(conflict, original: [:], model: model)
            fatalError("FAIL: overwrote another tool's role change")
        } catch is DisplayRoleError { checks += 1 }
        for invalid in ["false" as Any, 1 as Any] {
            do {
                _ = try DisplayRoleOverride.restoring(["DisplayIsTV": invalid], original: [:], model: model)
                fatalError("FAIL: accepted malformed role")
            } catch is DisplayRoleError { checks += 1 }
        }
        do {
            _ = try DisplayRoleOverride.dictionary(Data("invalid".utf8))
            fatalError("FAIL: accepted invalid plist")
        } catch { checks += 1 }
        expect(DisplayRoleOverride.bootID > 0, "boot identity available for restart status")
        print("PASS: \(checks) display role checks")
    }
}
