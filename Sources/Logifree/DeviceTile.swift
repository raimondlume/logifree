import LogifreeCore
import SwiftUI

/// One device: what it is, how it's connected, whether the agent applied your
/// settings, and its Easy-Switch channels drawn like the keys on the device.
struct DeviceTile: View {
    let model: AppModel
    let row: AppModel.DeviceRow

    @State private var switching: HostSlot?
    @State private var renaming: HostSlot?
    @State private var renameText = ""
    @State private var forgetting: HostSlot?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: row.isMouse ? "computermouse.fill" : "keyboard.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.name).font(.headline)
                    HStack(spacing: 10) {
                        if let note = row.note {
                            Text(note).foregroundStyle(.secondary)
                        } else {
                            Text(row.route).foregroundStyle(.secondary)
                            status
                        }
                    }
                    .font(.callout)
                }
                Spacer()
                if row.connected { manageMenu }
            }
            if !row.slots.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(row.slots, id: \.index) { slot in
                        let isCurrent = slot.index == row.currentChannel
                        Button { if row.connected, slot.paired, !isCurrent { switching = slot } } label: {
                            ChannelKey(slot: slot, isCurrent: isCurrent, isThisMac: isThisMac(slot, isCurrent: isCurrent))
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .help(help(for: slot, isCurrent: isCurrent))
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .opacity(row.connected ? 1 : 0.55)
        .animation(.easeOut(duration: 0.2), value: row.currentChannel)
        .confirmationDialog(
            "Switch to channel \((switching?.index ?? 0) + 1)?",
            isPresented: isPresent($switching), presenting: switching
        ) { slot in
            Button("Switch") { model.switchHost(row, to: slot) }
        } message: { slot in
            Text("\(row.name) will connect to \(slot.name.isEmpty ? "that computer" : slot.name) and stop working on this Mac.")
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
            Text("\(row.name) will unpair from \(slot.name.isEmpty ? "that computer" : slot.name). To use it there again, hold the device's channel \(slot.index + 1) button for 3 seconds, then pair it from that computer.")
        }
    }

    /// Silent when all is well; only in-progress and failures are news.
    @ViewBuilder private var status: some View {
        if let problem = row.problem {
            Label("Some settings didn't apply", systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .help(problem)
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
                    ForEach(row.slots.filter { $0.paired && $0.index != row.currentChannel }, id: \.index) { slot in
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

    /// The channel in use, or one paired to this Mac under its computer name
    /// (e.g. the same Mac over Bluetooth on another channel).
    private func isThisMac(_ slot: HostSlot, isCurrent: Bool) -> Bool {
        (isCurrent && row.connected) || (slot.paired && slot.name == Self.computerName)
    }

    private static let computerName = Host.current().localizedName ?? ""

    private func help(for slot: HostSlot, isCurrent: Bool) -> String {
        guard slot.paired else { return "Empty. Hold the device's channel \(slot.index + 1) button for 3 seconds to pair a computer." }
        let name = isThisMac(slot, isCurrent: isCurrent) ? "This Mac" : slot.name.isEmpty ? "Unnamed computer" : slot.name
        let via = slot.bus.isEmpty ? "" : " over \(slot.bus)"
        if isCurrent && row.connected { return "\(name)\(via). In use." }
        return row.connected ? "\(name)\(via). Click to switch." : "\(name)\(via)"
    }
}

/// An Easy-Switch key: LED on top, numbered keycap, then the computer and how
/// that channel connects.
private struct ChannelKey: View {
    let slot: HostSlot
    let isCurrent: Bool
    let isThisMac: Bool

    var body: some View {
        VStack(spacing: 7) {
            Circle()
                .fill(isCurrent ? Color.accentColor : Color.primary.opacity(0.12))
                .frame(width: 6, height: 6)
                .shadow(color: isCurrent ? Color.accentColor : .clear, radius: 4)
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
                        .strokeBorder(isCurrent ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.1))
                }
            VStack(spacing: 1) {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(isCurrent ? .primary : .secondary)
                if slot.paired, !slot.bus.isEmpty {
                    Text(slot.bus)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 140)
        }
        .contentShape(Rectangle())
    }

    private var caption: String {
        if isThisMac { return "This Mac" }
        if !slot.paired { return "Empty" }
        return slot.name.isEmpty ? "Unnamed computer" : slot.name
    }
}
