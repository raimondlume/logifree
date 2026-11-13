import AppKit
import LogifreeCore
import Observation
import ServiceManagement

/// State behind the settings window. Lives on main. Devices come from the agent's
/// status, and changes to them go through the agent, so the window never opens
/// a device itself (and needs no Input Monitoring).
@Observable
final class AppModel {
    /// A device as the window shows it. Kept after it leaves this Mac (with
    /// `device == nil`), so pressing an Easy-Switch button doesn't make it vanish.
    struct DeviceRow: Identifiable {
        var id: String { name }
        let name: String
        let isMouse: Bool
        var connected: Bool
        var route: String
        var problem: String?
        var slots: [HostSlot]
        var currentChannel: UInt8?
        var canForget: Bool
        /// Set while switching away or after leaving this Mac.
        var note: String?
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
    private(set) var agentStatus: AgentStatus? {
        didSet { agentStatusChanged() }
    }
    private(set) var devices: [DeviceRow] = []
    var error: AppError?

    @ObservationIgnored private let service = SMAppService.agent(plistName: "dev.raimond.logifree.agent.plist")
    @ObservationIgnored private var pendingSave: DispatchWorkItem?
    /// Commands sent to the agent, with the alert title to show if one fails.
    @ObservationIgnored private var sentCommands: [UUID: String] = [:]

    init() {
        AgentStatus.observeChanges { [weak self] in
            guard let self, agentEnabled else { return }
            agentStatus = AgentStatus.load()
        }
        refreshAgent()
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
        launchctl.arguments = ["kickstart", "gui/\(getuid())/dev.raimond.logifree.agent"]
        do { try launchctl.run() } catch {
            self.error = AppError(title: "Couldn't start Logifree", detail: error.localizedDescription)
            return
        }
        // If it isn't up shortly, launchd still has an older registration (e.g. the
        // agent moved inside the app after an update) and kickstart just hangs:
        // registering again makes launchd read the bundled plist.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
            if launchctl.isRunning { launchctl.terminate() }
            refreshAgent()
            guard !agentRunning else { return }
            try? service.unregister()
            setAgentEnabled(true)
        }
    }

    /// The agent's own little app inside ours; it's what needs Accessibility.
    var agentAppURL: URL {
        Bundle.main.bundleURL.appending(path: "Contents/Library/LoginItems/Logifree Agent.app")
    }

    /// Opens Accessibility settings with the agent ready to drag into the list.
    /// The agent only notices a new grant when asked, so ask it every second.
    func grantAccessibility() {
        PermissionGuide.shared.show(
            app: agentAppURL, pane: "Privacy_Accessibility",
            isGranted: { [weak self] in self?.agentStatus?.accessibility == true },
            tick: { Settings.postReload() }
        )
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

    // MARK: Devices

    private func agentStatusChanged() {
        guard agentRunning, let status = agentStatus else { return devices = [] }
        if let failure = status.failure, let title = sentCommands.removeValue(forKey: failure.command) {
            error = AppError(title: title, detail: failure.message)
        }
        merge(status.devices.map { state in
            var row = DeviceRow(
                name: state.name,
                isMouse: state.isMouse,
                connected: true,
                route: state.route,
                problem: state.problem,
                slots: state.slots,
                currentChannel: state.slots.first(where: \.isCurrent)?.index,
                canForget: state.canForget
            )
            if let channel = state.switchedTo {
                row.currentChannel = channel
                let name = state.slots.first { $0.index == channel }?.name ?? ""
                row.note = "Switched to \(name.isEmpty ? "channel \(channel + 1)" : name)"
            }
            return row
        })
    }

    /// New rows replace old ones by name; devices that disappeared stay, disconnected,
    /// so pressing an Easy-Switch button doesn't make them vanish.
    private func merge(_ fresh: [DeviceRow]) {
        var rows = devices.map { old -> DeviceRow in
            if let new = fresh.first(where: { $0.id == old.id }) { return new }
            var away = old
            away.connected = false
            if away.note == nil {
                away.currentChannel = nil
                away.note = "Not connected. It may be asleep or on another computer."
            }
            return away
        }
        rows += fresh.filter { new in !devices.contains { $0.id == new.id } }
        devices = rows
    }

    // MARK: Easy-Switch actions

    func switchHost(_ row: DeviceRow, to slot: HostSlot) {
        send(.switchHost(slot.index), to: row, failure: "Couldn't switch \(row.name) to channel \(slot.index + 1)")
    }

    func rename(_ row: DeviceRow, _ slot: HostSlot, to name: String) {
        send(.rename(slot.index, name), to: row, failure: "Couldn't rename channel \(slot.index + 1)")
    }

    func forget(_ row: DeviceRow, _ slot: HostSlot) {
        send(.forget(slot.index), to: row, failure: "Couldn't forget channel \(slot.index + 1)")
    }

    private func send(_ action: AgentCommand.Action, to row: DeviceRow, failure: String) {
        let command = AgentCommand(device: row.name, action: action)
        sentCommands[command.id] = failure
        do { try command.send() } catch {
            sentCommands[command.id] = nil
            self.error = AppError(title: failure, detail: error.localizedDescription)
        }
    }
}
