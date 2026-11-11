import AppKit
import IOKit.hid
import LogifreeCore
import Observation
import ServiceManagement

/// State behind the settings window. Lives on main; device I/O runs on `deviceQueue`.
@Observable
final class AppModel {
    struct DeviceRow: Identifiable {
        let id = UUID()
        let device: Device
        let slots: [HostSlot]
        let canForget: Bool
    }

    /// Saved (debounced) on change; the agent picks it up via the reload notification.
    var settings = Settings.load() {
        didSet { if settings != oldValue { scheduleSave() } }
    }
    private(set) var agentService: SMAppService.Status = .notRegistered
    private(set) var agentStatus: AgentStatus?
    private(set) var devices: [DeviceRow] = []
    private(set) var loadingDevices = false
    var error: AppError?

    struct AppError {
        let title: String
        let detail: String
    }

    @ObservationIgnored let inputMonitoringMissing: Bool
    @ObservationIgnored private let service = SMAppService.agent(plistName: "local.logifree.agent.plist")
    @ObservationIgnored private let browser: DeviceBrowser
    @ObservationIgnored private let deviceQueue = DispatchQueue(label: "devices")
    @ObservationIgnored private var pendingSave: DispatchWorkItem?

    init() {
        HIDPP.softwareID = 0x0C // don't collide with the agent or the CLI
        browser = DeviceBrowser()
        inputMonitoringMissing = browser.openResult == kIOReturnNotPermitted
        AgentStatus.observeChanges { [weak self] in
            guard let self, agentEnabled else { return }
            agentStatus = AgentStatus.load()
        }
        refreshAgent()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.refreshDevices() }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshAgent() } // e.g. back from granting a permission
    }

    // MARK: Agent

    var agentEnabled: Bool { agentService == .enabled }

    /// Enabled as a login item *and* its process is alive.
    var agentRunning: Bool {
        guard agentEnabled, let pid = agentStatus?.pid else { return false }
        return kill(pid, 0) == 0
    }

    func refreshAgent() {
        agentService = service.status
        guard agentEnabled else { return agentStatus = nil }
        agentStatus = AgentStatus.load()
        Settings.postReload() // the agent re-applies, then rewrites status.json
    }

    func setAgentEnabled(_ enabled: Bool) {
        do {
            if enabled { try service.register() } else { try service.unregister() }
        } catch {
            self.error = AppError(title: "Couldn't turn \(enabled ? "on" : "off") Start at login", detail: error.localizedDescription)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refreshAgent() }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let save = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do { try settings.save() } catch {
                self.error = AppError(title: "Couldn't save your settings", detail: error.localizedDescription)
            }
        }
        pendingSave = save
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: save)
    }

    /// What the agent last reported for this device, matched by name.
    func agentState(for device: Device) -> AgentStatus.DeviceState? {
        agentStatus?.devices.first { $0.name == device.name }
    }

    // MARK: Easy-Switch

    func refreshDevices(after delay: TimeInterval = 0) {
        loadingDevices = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            let transports = browser.currentTransports
            deviceQueue.async {
                let rows = DeviceBrowser.devices(on: transports).filter(\.hasEasySwitch).map {
                    DeviceRow(device: $0, slots: (try? $0.hostSlots()) ?? [], canForget: $0.canForgetHosts)
                }
                DispatchQueue.main.async {
                    self.devices = rows
                    self.loadingDevices = false
                }
            }
        }
    }

    func switchHost(_ row: DeviceRow, to slot: HostSlot) {
        perform("Couldn't switch \(row.device.name) to channel \(slot.index + 1)") { try row.device.switchHost(to: slot.index) }
        refreshDevices(after: 2) // it drops off this Mac
    }

    func rename(_ row: DeviceRow, _ slot: HostSlot, to name: String) {
        perform("Couldn't rename channel \(slot.index + 1)") { try row.device.renameHost(slot.index, to: name) }
        refreshDevices()
    }

    func forget(_ row: DeviceRow, _ slot: HostSlot) {
        perform("Couldn't forget channel \(slot.index + 1)") { try row.device.forgetHost(slot.index) }
        refreshDevices()
    }

    private func perform(_ failure: String, _ body: @escaping () throws -> Void) {
        deviceQueue.async {
            do { try body() } catch {
                let detail = "The device answered: \(error)."
                DispatchQueue.main.async { self.error = AppError(title: failure, detail: detail) }
            }
        }
    }
}
