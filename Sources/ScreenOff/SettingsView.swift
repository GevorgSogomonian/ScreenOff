import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: DisplayController
    var quit: () -> Void
    private let accent = Color(red: 0.08, green: 0.56, blue: 0.46)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accent.opacity(0.13))
                        .frame(width: 38, height: 38)
                    Image(systemName: "laptopcomputer")
                        .accessibilityLabel("Laptop")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("ScreenOff").font(.system(size: 16, weight: .semibold))
                    Text("Just the screen you need")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: quit) {
                    Image(systemName: "power").font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Quit ScreenOff and restore the built-in display")
                .accessibilityLabel("Quit ScreenOff")
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.bottom, 20)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Use built-in display")
                        .font(.system(size: 13, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("With an external monitor")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("Use built-in display with an external monitor",
                       isOn: Binding(get: { controller.usesBuiltInWithExternal },
                                     set: { controller.setUsesBuiltInWithExternal($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!controller.hardware.supported || controller.busy)
                    .accessibilityIdentifier("useBuiltInWithExternalToggle")
            }
            .padding(14)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.06), lineWidth: 1))

            HStack(alignment: .top, spacing: 7) {
                if controller.busy {
                    ProgressView().controlSize(.mini).scaleEffect(0.8)
                } else {
                    Circle()
                        .fill(controller.notice != nil ? Color.orange :
                                (controller.snapshot.externalDisplays.isEmpty ? Color.secondary : accent))
                        .frame(width: 6, height: 6).padding(.top, 4)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(controller.statusText)
                    if let loginNotice = controller.loginNotice { Text(loginNotice) }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.top, 14)

        }
        .padding(20)
        .frame(width: 374)
        .tint(accent)
        .accentColor(accent)
    }
}
