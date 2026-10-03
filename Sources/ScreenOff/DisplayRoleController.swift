import AppKit
import CoreGraphics
import Combine

struct DisplayRoleRow: Identifiable, Equatable {
    let model: DisplayModel
    let name: String
    let connected: Bool
    let excluded: Bool
    let status: String
    var id: String { model.id }
}

@MainActor
final class DisplayRoleController: ObservableObject {
    @Published private(set) var rows: [DisplayRoleRow] = []
    @Published private(set) var busy = false
    @Published private(set) var notice: String?
    let previewOnly: Bool

    init(previewOnly: Bool) { self.previewOnly = previewOnly; refresh() }

    func refresh() {
        guard !previewOnly else {
            rows = [DisplayRoleRow(model: DisplayModel(vendor: 4268, product: 1234), name: "External monitor",
                                   connected: true, excluded: false, status: "Uses macOS Night Shift")]
            return
        }
        var models: [DisplayModel: (String, Bool)] = [:]
        var ids = [CGDirectDisplayID](repeating: 0, count: 128)
        var count: UInt32 = 0
        if CGGetOnlineDisplayList(128, &ids, &count) == .success, count < 128 {
            for id in ids.prefix(Int(count)) where CGDisplayIsBuiltin(id) == 0 {
                let model = DisplayModel(vendor: CGDisplayVendorNumber(id), product: CGDisplayModelNumber(id))
                guard DisplayHardwareIdentity.isUsableExternal(vendor: model.vendor, model: model.product) else { continue }
                let screen = NSScreen.screens.first {
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
                }
                models[model] = (screen?.localizedName ?? "External monitor (\(model.id))", true)
            }
        }
        // Keep recovery available even when the monitor is unplugged.
        let directory = "/Library/Application Support/ScreenOff/DisplayRoles"
        for file in (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [] where file.hasSuffix(".plist") {
            let parts = String(file.dropLast(6)).split(separator: "-")
            guard parts.count == 2, let vendor = UInt32(parts[0], radix: 16), let product = UInt32(parts[1], radix: 16) else { continue }
            let model = DisplayModel(vendor: vendor, product: product)
            if models[model] == nil {
                models[model] = (UserDefaults.standard.string(forKey: "displayRoleName.\(model.id)") ?? "Monitor (\(model.id))", false)
            }
        }
        let updated = models.map { model, description -> DisplayRoleRow in
            var excluded = false
            var status = description.1 ? "Uses macOS Night Shift" : "Disconnected"
            do {
                if FileManager.default.fileExists(atPath: model.recordPath) {
                    let record = try DisplayRoleOverride.dictionary(Data(contentsOf: URL(fileURLWithPath: model.recordPath)))
                    guard let saved = record["excluded"] as? Bool else { throw DisplayRoleError(message: "Recovery record needs attention") }
                    excluded = saved
                    let current = FileManager.default.fileExists(atPath: model.overridePath)
                        ? try DisplayRoleOverride.dictionary(Data(contentsOf: URL(fileURLWithPath: model.overridePath))) : [:]
                    if saved && current["DisplayIsTV"] as? Bool != true {
                        status = "Setting changed or apply incomplete; restore before retrying"
                    } else if DisplayRoleOverride.bootID == 0 || (record["boot"] as? NSNumber)?.int64Value == DisplayRoleOverride.bootID {
                        status = "Restart your Mac to apply this change"
                    } else {
                        status = saved ? "Exclusion configured" : "Original setting restored"
                    }
                }
            } catch { status = "Cannot read settings: \(error.localizedDescription)" }
            if !description.1 && !status.hasPrefix("Disconnected") { status += " · Disconnected" }
            return DisplayRoleRow(model: model, name: description.0, connected: description.1, excluded: excluded, status: status)
        }.sorted { $0.id < $1.id }
        if rows != updated { rows = updated }
    }

    func setExcluded(_ excluded: Bool, row: DisplayRoleRow) {
        guard !previewOnly, !busy, !excluded || row.connected else { return }
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/ScreenOffDisplayRole").path
        guard FileManager.default.isExecutableFile(atPath: helper) else {
            notice = "The display-role helper is missing. Reinstall ScreenOff."; return
        }
        busy = true
        notice = nil
        UserDefaults.standard.set(row.name, forKey: "displayRoleName.\(row.id)")
        let command = Self.shellQuote(helper) + " " + (excluded ? "exclude" : "restore")
            + " \(row.model.vendor) \(row.model.product)"
        let script = "do shell script \(Self.appleScriptString(command)) with administrator privileges"
        Task {
            let result: String? = await Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                let pipe = Pipe()
                process.standardError = pipe
                process.standardOutput = FileHandle.nullDevice
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 { return nil }
                    let error = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    return error.contains("(-128)") ? "Change cancelled; settings were not applied." : error
                } catch { return error.localizedDescription }
            }.value
            self.busy = false
            self.notice = result
            self.refresh()
        }
    }

    static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func appleScriptString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
