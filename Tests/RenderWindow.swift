import AppKit
import SwiftUI

@main
enum RenderWindow {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .aqua)
        let hardware = DisplayHardware()
        let on = (try? hardware.snapshot().builtInIsOn) ?? true
        let controller = DisplayController(testing: true, hardware: hardware,
                                           automaticPreference: !on, previewOnly: true)
        let view = NSHostingView(rootView: SettingsView(controller: controller, quit: {})
            .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light))
        view.appearance = NSAppearance(named: .aqua)
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("Rendered native settings: \(Int(view.frame.width)) × \(Int(view.frame.height)) pt")
    }
}
