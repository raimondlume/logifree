import LogifreeCore
import ServiceManagement
import SwiftUI

struct ContentView: View {
    @State private var model = AppModel()
    @State private var renaming: (AppModel.DeviceRow, HostSlot)?
    @State private var renameText = ""
    @State private var forgetting: (AppModel.DeviceRow, HostSlot)?

    var body: some View {
        Form {
            agentSection
            scrollingSection
            gestureSection
            easySwitchSections
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 720)
        .alert("Rename slot", isPresented: isPresent($renaming)) {
            TextField("Name", text: $renameText)
            Button("Rename") { if let (row, slot) = renaming { model.rename(row, slot, to: renameText) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Forget this slot?", isPresented: isPresent($forgetting), presenting: forgetting
        ) { row, slot in
            Button("Forget \(slot.name.isEmpty ? "slot \(slot.index + 1)" : slot.name)", role: .destructive) {
                model.forget(row, slot)
            }
        } message: { _, _ in
            Text("The device unpairs from that host. To use it there again, pair it from the device.")
        }
        .alert("Something went wrong", isPresented: isPresent($model.error)) {} message: {
            Text(model.error ?? "")
        }
    }

    // MARK: Sections

    private var agentSection: some View {
        Section {
            Toggle("Start at login", isOn: Binding(
                get: { model.agentService == .enabled || model.agentService == .requiresApproval },
                set: { model.setAgentEnabled($0) }
            ))
            if model.agentService == .requiresApproval {
                LabeledContent("Waiting for approval in Login Items") {
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            if model.agentRunning {
                LabeledContent("Accessibility") {
                    if model.agentStatus?.accessibility == true {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Grant…") { openPrivacyPane("Privacy_Accessibility") }
                    }
                }
            }
            if model.inputMonitoringMissing {
                LabeledContent("Input Monitoring is needed to talk to devices") {
                    Button("Grant…") { openPrivacyPane("Privacy_ListenEvent") }
                }
            }
        } header: {
            Text("Agent")
        } footer: {
            Text("Keeps a small background agent running, now and after every login. It applies these settings whenever a device connects, and needs Accessibility (granted to logifree-agent) for gesture actions, which send keyboard shortcuts.")
                .foregroundStyle(.secondary)
        }
    }

    private var scrollingSection: some View {
        Section {
            Toggle("Reverse scroll wheel", isOn: $model.settings.invertWheel)
            Toggle("Reverse thumb wheel", isOn: $model.settings.invertThumbwheel)
        } header: {
            Text("Scrolling")
        } footer: {
            Text("Set in the mouse itself, so the trackpad keeps the system direction.")
                .foregroundStyle(.secondary)
        }
    }

    private var gestureSection: some View {
        Section {
            ForEach(ThumbGesture.allCases, id: \.self) { gesture in
                GestureRow(gesture: gesture, action: Binding(
                    get: { model.settings.gestures[gesture] },
                    set: { model.settings.gestures[gesture] = $0 }
                ))
            }
            LabeledContent("Swipe distance") {
                Slider(
                    value: Binding(
                        get: { Double(model.settings.swipeThreshold) },
                        set: { model.settings.swipeThreshold = Int($0) }
                    ),
                    in: 20...200
                ) {} minimumValueLabel: { Text("Short") } maximumValueLabel: { Text("Long") }
                .frame(width: 220)
            }
        } header: {
            Text("Gesture button")
        } footer: {
            Text("Click the thumb button, or hold it and move the mouse.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var easySwitchSections: some View {
        if model.devices.isEmpty {
            Section {
                Text(model.loadingDevices ? "Looking for devices…" : "No Easy-Switch devices connected.")
                    .foregroundStyle(.secondary)
            } header: {
                easySwitchHeader(nil)
            }
        }
        ForEach(model.devices) { row in
            Section {
                ForEach(row.slots, id: \.index) { slot in slotRow(row, slot) }
            } header: {
                easySwitchHeader(row)
            }
        }
    }

    private func easySwitchHeader(_ row: AppModel.DeviceRow?) -> some View {
        HStack {
            if let row {
                Text("Easy-Switch · \(row.device.name)")
            } else {
                Text("Easy-Switch")
            }
            Spacer()
            if row == nil || row?.id == model.devices.first?.id {
                if model.loadingDevices {
                    ProgressView().controlSize(.small)
                } else {
                    Button { model.refreshDevices() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help("Look for devices again")
                }
            }
        }
    }

    private func slotRow(_ row: AppModel.DeviceRow, _ slot: HostSlot) -> some View {
        HStack(spacing: 12) {
            Text("\(slot.index + 1)").monospacedDigit().foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.paired ? (slot.name.isEmpty ? "Unnamed" : slot.name) : "Empty")
                    .foregroundStyle(slot.paired ? .primary : .secondary)
                if slot.paired, !slot.bus.isEmpty {
                    Text(slot.bus).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if slot.isCurrent {
                Text("This Mac").font(.caption).foregroundStyle(.secondary)
            } else if slot.paired {
                Button("Switch") { model.switchHost(row, to: slot) }
            }
            if slot.paired {
                Menu {
                    Button("Rename…") {
                        renameText = slot.name
                        renaming = (row, slot)
                    }
                    if row.canForget, !slot.isCurrent {
                        Button("Forget…", role: .destructive) { forgetting = (row, slot) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }

    private func openPrivacyPane(_ anchor: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }

    private func isPresent<T>(_ binding: Binding<T?>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue != nil }, set: { if !$0 { binding.wrappedValue = nil } })
    }
}

// MARK: - ThumbGesture row

private enum ActionChoice: CaseIterable, Hashable {
    case none, missionControl, appExpose, showDesktop, desktopLeft, desktopRight, keystroke, shell

    init(_ action: Action?) {
        switch action {
        case nil: self = .none
        case .missionControl: self = .missionControl
        case .appExpose: self = .appExpose
        case .showDesktop: self = .showDesktop
        case .desktopLeft: self = .desktopLeft
        case .desktopRight: self = .desktopRight
        case .keystroke: self = .keystroke
        case .shell: self = .shell
        }
    }

    var title: String {
        switch self {
        case .none: "Nothing"
        case .missionControl: "Mission Control"
        case .appExpose: "App Exposé"
        case .showDesktop: "Show Desktop"
        case .desktopLeft: "Previous desktop"
        case .desktopRight: "Next desktop"
        case .keystroke: "Keyboard shortcut"
        case .shell: "Shell command"
        }
    }

    var action: Action? {
        switch self {
        case .none: nil
        case .missionControl: .missionControl
        case .appExpose: .appExpose
        case .showDesktop: .showDesktop
        case .desktopLeft: .desktopLeft
        case .desktopRight: .desktopRight
        case .keystroke: .keystroke(.unset)
        case .shell: .shell("")
        }
    }
}

private struct GestureRow: View {
    let gesture: ThumbGesture
    @Binding var action: Action?

    var body: some View {
        LabeledContent(title) {
            HStack {
                if case .keystroke(let combo) = action {
                    ShortcutRecorder(combo: Binding(get: { combo }, set: { action = .keystroke($0) }))
                }
                if case .shell(let command) = action {
                    TextField("open -a Notes", text: Binding(get: { command }, set: { action = .shell($0) }))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                }
                Picker("", selection: Binding(
                    get: { ActionChoice(action) },
                    set: { if $0 != ActionChoice(action) { action = $0.action } }
                )) {
                    ForEach(ActionChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var title: String {
        switch gesture {
        case .click: "Click"
        case .swipeUp: "Swipe up"
        case .swipeDown: "Swipe down"
        case .swipeLeft: "Swipe left"
        case .swipeRight: "Swipe right"
        }
    }
}
