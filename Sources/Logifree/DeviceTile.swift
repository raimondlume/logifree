import LogifreeCore
import SwiftUI

/// One connected device: what it is, how it's connected, whether the agent
/// applied your settings, and its Easy-Switch channels drawn like the keys on
/// the device itself.
struct DeviceTile: View {
    let model: AppModel
    let row: AppModel.DeviceRow

    @State private var switching: HostSlot?
    @State private var renaming: HostSlot?
    @State private var renameText = ""
    @State private var forgetting: HostSlot?

    private var device: Device { row.device }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: device.isMouse ? "computermouse.fill" : "keyboard.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name).font(.headline)
                    HStack(spacing: 10) {
                        Text(device.transport.kind == .bluetooth ? "Bluetooth" : "Bolt receiver")
                            .foregroundStyle(.secondary)
                        status
                    }
                    .font(.callout)
                }
                Spacer()
                manageMenu
            }
            if !row.slots.isEmpty {
                HStack(spacing: 0) {
                    ForEach(row.slots, id: \.index) { slot in
                        Button { if slot.paired, !slot.isCurrent { switching = slot } } label: {
                            ChannelKey(slot: slot)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .help(help(for: slot))
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .confirmationDialog(
            "Switch to channel \((switching?.index ?? 0) + 1)?",
            isPresented: isPresent($switching), presenting: switching
        ) { slot in
            Button("Switch") { model.switchHost(row, to: slot) }
        } message: { slot in
            Text("\(device.name) will connect to \(slot.name.isEmpty ? "that computer" : slot.name) and stop working on this Mac.")
        }
        .alert("Rename channel \((renaming?.index ?? 0) + 1)", isPresented: isPresent($renaming)) {
            TextField("Name", text: $renameText)
            Button("Rename") { if let renaming { model.rename(row, renaming, to: renameText) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Forget channel \((forgetting?.index ?? 0) + 1)?",
            isPresented: isPresent($forgetting), presenting: forgetting
        ) { slot in
            Button("Forget", role: .destructive) { model.forget(row, slot) }
        } message: { slot in
            Text("\(device.name) unpairs from \(slot.name.isEmpty ? "that computer" : slot.name). To use it there again, pair it from the device.")
        }
    }

    @ViewBuilder private var status: some View {
        if model.agentRunning, device.isMouse {
            if let state = model.agentState(for: device) {
                if let problem = state.problem {
                    Label("Some settings didn't apply", systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .help(problem)
                } else {
                    Label("Settings applied", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else {
                Text("Waiting for Logifree").foregroundStyle(.tertiary)
            }
        }
    }

    private var manageMenu: some View {
        Menu {
            Section("Rename") {
                ForEach(row.slots.filter(\.paired), id: \.index) { slot in
                    Button("Channel \(slot.index + 1)…") {
                        renameText = slot.name
                        renaming = slot
                    }
                }
            }
            if row.canForget {
                Section("Forget") {
                    ForEach(row.slots.filter { $0.paired && !$0.isCurrent }, id: \.index) { slot in
                        Button("Channel \(slot.index + 1)…", role: .destructive) { forgetting = slot }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Rename or forget channels")
    }

    private func help(for slot: HostSlot) -> String {
        guard slot.paired else { return "Empty. Hold the device's channel \(slot.index + 1) button to pair a computer." }
        let name = slot.name.isEmpty ? "Unnamed computer" : slot.name
        let via = slot.bus.isEmpty ? "" : " over \(slot.bus)"
        return slot.isCurrent ? "\(name)\(via). This Mac." : "\(name)\(via). Click to switch."
    }
}

/// An Easy-Switch key: LED on top, numbered keycap, the computer's name below.
private struct ChannelKey: View {
    let slot: HostSlot

    var body: some View {
        VStack(spacing: 7) {
            Circle()
                .fill(slot.isCurrent ? Color.accentColor : Color.primary.opacity(0.12))
                .frame(width: 6, height: 6)
                .shadow(color: slot.isCurrent ? Color.accentColor : .clear, radius: 4)
            Text("\(slot.index + 1)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(slot.paired ? .primary : .tertiary)
                .frame(width: 42, height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.3), radius: 0.5, y: 1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(slot.isCurrent ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.1))
                }
            Text(caption)
                .font(.caption)
                .foregroundStyle(slot.isCurrent ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 140)
        }
        .contentShape(Rectangle())
    }

    private var caption: String {
        if slot.isCurrent { return "This Mac" }
        if !slot.paired { return "Empty" }
        return slot.name.isEmpty ? "Unnamed" : slot.name
    }
}
