import Foundation
import notify

public enum ThumbGesture: String, Codable, CaseIterable, CodingKeyRepresentable {
    case click, swipeUp, swipeDown, swipeLeft, swipeRight

    /// Hold-and-move distance (raw sensor counts) → gesture.
    public static func classify(dx: Int, dy: Int, threshold: Int) -> ThumbGesture {
        if max(abs(dx), abs(dy)) < threshold { return .click }
        if abs(dx) > abs(dy) { return dx < 0 ? .swipeLeft : .swipeRight }
        return dy < 0 ? .swipeUp : .swipeDown
    }
}

public struct KeyCombo: Codable, Hashable {
    /// macOS virtual key code; `nil` until one is recorded.
    public var key: UInt16?
    /// `CGEventFlags` / `NSEvent.ModifierFlags` raw value (same bits).
    public var modifiers: UInt64
    /// What to show in the UI, e.g. "⌘⇧4".
    public var display: String

    public init(key: UInt16?, modifiers: UInt64, display: String) {
        self.key = key
        self.modifiers = modifiers
        self.display = display
    }

    public static let unset = KeyCombo(key: nil, modifiers: 0, display: "")
}

public enum Action: Codable, Hashable {
    case missionControl
    case appExpose
    case showDesktop
    case desktopLeft
    case desktopRight
    case keystroke(KeyCombo)
    case shell(String)
}

/// Lives in `~/Library/Application Support/logifree/settings.json`. The app writes
/// it and posts `reloadNotification`; the agent re-reads and re-applies.
public struct Settings: Codable, Equatable {
    public var invertWheel = true
    public var invertThumbwheel = true
    public var gestures: [ThumbGesture: Action] = [
        .click: .missionControl,
        .swipeUp: .missionControl,
        .swipeDown: .appExpose,
        .swipeLeft: .desktopLeft,
        .swipeRight: .desktopRight,
    ]
    public var swipeThreshold = 50
    /// Slow wheel clicks scroll at least this many lines; 1 = macOS default.
    /// Faster scrolling, which macOS already accelerates past this, is untouched.
    public var minimumLinesPerClick = 2
    /// System-wide key → key remaps for every keyboard.
    public var keyRemaps: [KeyRemap] = []

    public init() {}

    // Missing keys fall back to defaults, so adding a setting never breaks an old file.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()
        invertWheel = try container.decodeIfPresent(Bool.self, forKey: .invertWheel) ?? defaults.invertWheel
        invertThumbwheel = try container.decodeIfPresent(Bool.self, forKey: .invertThumbwheel) ?? defaults.invertThumbwheel
        gestures = try container.decodeIfPresent([ThumbGesture: Action].self, forKey: .gestures) ?? defaults.gestures
        swipeThreshold = try container.decodeIfPresent(Int.self, forKey: .swipeThreshold) ?? defaults.swipeThreshold
        minimumLinesPerClick = try container.decodeIfPresent(Int.self, forKey: .minimumLinesPerClick)
            ?? defaults.minimumLinesPerClick
        keyRemaps = try container.decodeIfPresent([KeyRemap].self, forKey: .keyRemaps) ?? defaults.keyRemaps
    }

    public static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/logifree")
    public static let url = directory.appendingPathComponent("settings.json")
    public static let reloadNotification = "dev.raimond.logifree.reload"

    public static func load() -> Settings {
        guard let data = try? Data(contentsOf: url) else { return Settings() }
        do {
            return try JSONDecoder().decode(Settings.self, from: data)
        } catch {
            Log.info("settings.json unreadable, using defaults: \(error)")
            return Settings()
        }
    }

    /// Write, then tell the agent.
    public func save() throws {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Self.url, options: .atomic)
        Self.postReload()
    }

    public static func postReload() { notify_post(reloadNotification) }

    /// Calls `handler` on main whenever someone posts `reloadNotification`.
    public static func observeReload(_ handler: @escaping () -> Void) {
        var token: Int32 = 0
        notify_register_dispatch(reloadNotification, &token, .main) { _ in handler() }
    }
}

/// What the agent reports about itself, for the app to show. Rewritten by the
/// agent on start and on every reload.
public struct AgentStatus: Codable {
    /// A device the agent has configured, and what went wrong if anything did.
    public struct DeviceState: Codable {
        public var name: String
        public var problem: String?

        public init(name: String, problem: String?) {
            self.name = name
            self.problem = problem
        }
    }

    public var pid: Int32
    public var accessibility: Bool
    public var devices: [DeviceState]

    public init(accessibility: Bool, devices: [DeviceState]) {
        pid = getpid()
        self.accessibility = accessibility
        self.devices = devices
    }

    public static let url = Settings.directory.appendingPathComponent("status.json")

    public static func load() -> AgentStatus? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AgentStatus.self, from: data)
    }

    public func save() {
        try? FileManager.default.createDirectory(at: Settings.directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: Self.url, options: .atomic)
        notify_post(Self.changedNotification)
    }

    public static let changedNotification = "dev.raimond.logifree.status"
    /// Posted by the app to make the agent undo its changes and exit.
    public static let quitNotification = "dev.raimond.logifree.quit"

    public static func postQuit() { notify_post(quitNotification) }

    public static func observeQuit(_ handler: @escaping () -> Void) {
        var token: Int32 = 0
        notify_register_dispatch(quitNotification, &token, .main) { _ in handler() }
    }

    /// Calls `handler` on main whenever the agent rewrites its status.
    public static func observeChanges(_ handler: @escaping () -> Void) {
        var token: Int32 = 0
        notify_register_dispatch(changedNotification, &token, .main) { _ in handler() }
    }
}
