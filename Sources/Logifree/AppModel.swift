import AppKit
import IOKit.hid
import LogifreeCore
import Observation
import ServiceManagement

/// State behind the settings window. Lives on main; device I/O runs on `deviceQueue`.
@Observable
final class AppModel {
    /// A device as the window shows it. Kept after it leaves this Mac (with
    /// `device == nil`), so pressing an Easy-Switch button doesn't make it vanish.
    struct DeviceRow: Identifiable {
        var id: String { name }
        let name: String
        let isMouse: Bool
        var device: Device?
        var route: String
        var slots: [HostSlot]
        var currentChannel: UInt8?
        var canForget: Bool
        /// Feature index of Change Host, to recognise "switching channel" events.
        var changeHostIndex: UInt8?
        /// Set while switching away or after leaving this Mac.
        var note: String?

        var connected: Bool { device != nil }
    }

    struct AppError {
        let title: String
        let detail: String
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

    @ObservationIgnored let inputMonitoringMissing: Bool
    @ObservationIgnored private let service = SMAppService.agent(plistName: "local.logifree.agent.plist")
    @ObservationIgnored private let browser: DeviceBrowser
    @ObservationIgnored private let deviceQueue = DispatchQueue(label: "devices")
    @ObservationIgnored private var pendingSave: DispatchWorkItem?
    @ObservationIgnored private var pendingRefresh: DispatchWorkItem?

    init() {
        HIDPP.softwareID = 0x0C // don't collide with the agent or the CLI
        browser = DeviceBrowser()
        inputMonitoringMissing = browser.openResult == kIOReturnNotPermitted
        browser.onChange = { [weak self] in self?.scheduleRefresh() }
        browser.onReport = { [weak self] in self?.deviceEvent($0, $1) }
        AgentStatus.observeChanges { [weak self] in
            guard let self, agentEnabled else { return }
            agentStatus = AgentStatus.load()
        }
        refreshAgent()
        scheduleRefresh(after: 0.3)
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

    /// Launch the agent now (it's stopped after a quit until the next login).
    func startAgent() {
        let launchctl = Process()
        launchctl.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        launchctl.arguments = ["kickstart", "gui/\(getuid())/local.logifree.agent"]
        do { try launchctl.run() } catch {
            self.error = AppError(title: "Couldn't start Logifree", detail: error.localizedDescription)
        }
    }

    /// Stop the agent (it restores your devices first) and close the app.
    static func quitCompletely() {
        AgentStatus.postQuit()
        NSApp.terminate(nil)
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
    func agentState(for row: DeviceRow) -> AgentStatus.DeviceState? {
        agentStatus?.devices.first { $0.name == row.name }
    }

    // MARK: Devices

    /// Debounced: one Easy-Switch press produces a burst of events.
    func scheduleRefresh(after delay: TimeInterval = 0.6) {
        pendingRefresh?.cancel()
        let refresh = DispatchWorkItem { [weak self] in self?.refreshDevices() }
        pendingRefresh = refresh
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: refresh)
    }

    func refreshDevices() {
        loadingDevices = true
        let transports = browser.currentTransports
        deviceQueue.async {
            let fresh = DeviceBrowser.devices(on: transports).filter(\.hasEasySwitch).map { device in
                let slots = (try? device.hostSlots()) ?? []
                return DeviceRow(
                    name: device.name,
                    isMouse: device.isMouse,
                    device: device,
                    route: device.transport.kind == .bluetooth ? "Bluetooth" : "Bolt receiver",
                    slots: slots,
                    currentChannel: slots.first(where: \.isCurrent)?.index,
                    canForget: device.canForgetHosts,
                    changeHostIndex: try? device.featureIndex(HIDPP.Feature.changeHost)
                )
            }
            DispatchQueue.main.async { self.merge(fresh) }
        }
    }

    /// New rows replace old ones by name; devices that disappeared stay, disconnected.
    private func merge(_ fresh: [DeviceRow]) {
        var rows = devices.map { old -> DeviceRow in
            if let new = fresh.first(where: { $0.id == old.id }) { return new }
            var away = old
            away.device = nil
            if away.note == nil {
                away.currentChannel = nil
                away.note = "Not connected. It may be asleep or on another computer."
            }
            return away
        }
        rows += fresh.filter { new in !devices.contains { $0.id == new.id } }
        devices = rows
        loadingDevices = false
    }

    /// Receiver connection notices and "switching channel" announcements.
    private func deviceEvent(_ transport: Transport, _ report: [UInt8]) {
        if report[0] == 0x10 && report[2] == 0x41 { return scheduleRefresh() }

        // Change Host event 0 (software ID 0): [from, to], sent just before the device leaves.
        guard report[0] == 0x11, report[3] == 0x00,
              let index = devices.firstIndex(where: {
                  $0.device?.transport === transport && $0.device?.index == report[1] && $0.changeHostIndex == report[2]
              })
        else { return }
        announceSwitch(of: index, to: report[5])
        scheduleRefresh(after: 1.5)
    }

    private func announceSwitch(of index: Int, to channel: UInt8) {
        devices[index].currentChannel = channel
        let name = devices[index].slots.first { $0.index == channel }?.name ?? ""
        devices[index].note = "Switched to \(name.isEmpty ? "channel \(channel + 1)" : name)"
    }

    // MARK: Easy-Switch actions

    func switchHost(_ row: DeviceRow, to slot: HostSlot) {
        guard let device = row.device else { return }
        if let index = devices.firstIndex(where: { $0.id == row.id }) { announceSwitch(of: index, to: slot.index) }
        perform("Couldn't switch \(row.name) to channel \(slot.index + 1)") { try device.switchHost(to: slot.index) }
        scheduleRefresh(after: 2)
    }

    func rename(_ row: DeviceRow, _ slot: HostSlot, to name: String) {
        guard let device = row.device else { return }
        perform("Couldn't rename channel \(slot.index + 1)") { try device.renameHost(slot.index, to: name) }
        scheduleRefresh(after: 0)
    }

    func forget(_ row: DeviceRow, _ slot: HostSlot) {
        guard let device = row.device else { return }
        perform("Couldn't forget channel \(slot.index + 1)") { try device.forgetHost(slot.index) }
        scheduleRefresh(after: 0)
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
