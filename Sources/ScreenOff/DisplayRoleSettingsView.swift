import SwiftUI

struct DisplayRoleSettingsView: View {
    @StateObject private var controller: DisplayRoleController
    let topology: DisplaySnapshot
    let displayBusy: Bool

    init(topology: DisplaySnapshot, displayBusy: Bool, previewOnly: Bool) {
        self.topology = topology
        self.displayBusy = displayBusy
        _controller = StateObject(wrappedValue: DisplayRoleController(previewOnly: previewOnly))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exclude from Night Shift").font(.system(size: 13, weight: .medium))
            Text("Use an external monitor’s own eye-care mode. Also disables True Tone. Applies to every monitor of the same model.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if controller.rows.isEmpty {
                Text("Connect an external monitor to configure it.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach(controller.rows) { row in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.name).font(.system(size: 12, weight: .medium))
                        Text(row.status).font(.system(size: 11)).foregroundStyle(.secondary)
                    }.fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Toggle("Exclude \(row.name) from Night Shift", isOn: Binding(
                        get: { row.excluded }, set: { controller.setExcluded($0, row: row) }))
                        .labelsHidden().toggleStyle(.switch)
                        .disabled(controller.previewOnly || controller.busy || displayBusy || (!row.connected && !row.excluded))
                        .accessibilityIdentifier("excludeNightShift.\(row.id)")
                }
            }
            Text("Changes require an administrator password and a Mac restart. Turn the switch off to restore the original setting before uninstalling ScreenOff.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if controller.busy { ProgressView("Waiting for administrator approval…").controlSize(.small).font(.system(size: 11)) }
            if let notice = controller.notice {
                Text(notice).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .onAppear { controller.refresh() }
        .onChange(of: topology) { _ in controller.refresh() }
    }
}
