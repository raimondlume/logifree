import LogifreeCore
import ServiceManagement
import SwiftUI

struct ContentView: View {
    @State private var model = AppModel()

    var body: some View {
        Form {
            agentSection
            devicesSection
            scrollingSection
            gestureSection
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 760)
        .alert(model.error?.title ?? "", isPresented: isPresent($model.error)) {} message: {
            Text(model.error?.detail ?? "")
        }
    }

    // MARK: Agent

    private var agentSection: some View {
        Section {
            HStack(spacing: 10) {
                Circle()
                    .fill(model.agentRunning ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(agentHeadline)
                    .layoutPriority(1)
                Spacer()
                Text("Start at login")
                    .foregroundStyle(.secondary)
                Toggle("Start at login", isOn: Binding(
                    get: { model.agentService == .enabled || model.agentService == .requiresApproval },
                    set: { model.setAgentEnabled($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }
            if model.agentService == .requiresApproval {
                notice("Approve Logifree in Login Items to start it.", button: "Open Login Items") {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
            if model.agentRunning, model.agentStatus?.accessibility == false {
                notice("Gesture actions need Accessibility access for logifree-agent.", button: "Open Settings") {
                    openPrivacyPane("Privacy_Accessibility")
                }
            }
            if model.inputMonitoringMissing {
                notice("Logifree needs Input Monitoring access to find your devices.", button: "Open Settings") {
                    openPrivacyPane("Privacy_ListenEvent")
                }
            }
        } footer: {
            if model.agentEnabled, !model.agentRunning {
                Text("Start at login is on, but Logifree isn't running. Turn the switch off and on again to restart it.")
                    .foregroundStyle(.secondary)
            } else if !model.agentRunning {
                Text("Your settings only take effect while Logifree runs in the background.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var agentHeadline: String {
        if model.agentRunning { return "Running in the background" }
        if model.agentService == .requiresApproval { return "Waiting for approval" }
        return "Not running"
    }

    private func notice(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
            Spacer()
            Button(button, action: action)
        }
    }

    // MARK: Devices

    private var devicesSection: some View {
        Section {
            if model.devices.isEmpty {
                HStack {
                    Text(model.loadingDevices
                         ? "Looking for devices…"
                         : "No devices found. Move your mouse or press a key to wake them.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.loadingDevices { ProgressView().controlSize(.small) }
                }
            }
            ForEach(model.devices) { row in
                DeviceTile(model: model, row: row)
            }
        } header: {
            HStack {
                Text("Devices")
                Spacer()
                Button { model.refreshDevices() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.loadingDevices)
                .help("Look for devices again")
            }
        }
    }

    // MARK: Mouse settings

    private var scrollingSection: some View {
        Section {
            Toggle("Reverse scroll wheel", isOn: $model.settings.invertWheel)
            Toggle("Reverse thumb wheel", isOn: $model.settings.invertThumbwheel)
            Picker("Distance per click", selection: $model.settings.minimumLinesPerClick) {
                Text("macOS default").tag(1)
                Text("2 lines").tag(2)
                Text("3 lines").tag(3)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Scrolling")
        } footer: {
            Text("A slow click scrolls at least this far. Faster scrolling keeps macOS's own acceleration. Your trackpad isn't affected.")
                .foregroundStyle(.secondary)
        }
    }

    private var gestureSection: some View {
        Section {
            GesturePad(gestures: $model.settings.gestures)
            LabeledContent("Swipe distance") {
                Slider(
                    value: Binding(
                        get: { Double(model.settings.swipeThreshold) },
                        set: { model.settings.swipeThreshold = Int($0) }
                    ),
                    in: 20...200
                ) {} minimumValueLabel: {
                    Text("Short").font(.caption)
                } maximumValueLabel: {
                    Text("Long").font(.caption)
                }
                .frame(width: 240)
            }
        } header: {
            Text("Gesture button")
        } footer: {
            Text("Click the thumb button, or hold it and move the mouse in a direction.")
                .foregroundStyle(.secondary)
        }
    }

    private func openPrivacyPane(_ anchor: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }
}

func isPresent<T>(_ binding: Binding<T?>) -> Binding<Bool> {
    Binding(get: { binding.wrappedValue != nil }, set: { if !$0 { binding.wrappedValue = nil } })
}
