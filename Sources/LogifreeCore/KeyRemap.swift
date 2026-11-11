import Foundation
import IOKit.hidsystem

/// One key → key remap, by HID keyboard usage (page 7). Applied system-wide to
/// every keyboard through macOS's own `UserKeyMapping` (what `hidutil` sets),
/// so it costs nothing per keypress.
public struct KeyRemap: Codable, Hashable {
    public var from: UInt16
    public var to: UInt16

    public init(from: UInt16, to: UInt16) {
        self.from = from
        self.to = to
    }

    /// Replace the system's key remaps with `remaps` (empty clears them).
    /// macOS forgets these at logout, which is why the agent sets them on start.
    @discardableResult
    public static func apply(_ remaps: [KeyRemap]) -> Bool {
        let mapping = remaps.map {
            ["HIDKeyboardModifierMappingSrc": 0x7_0000_0000 | UInt64($0.from),
             "HIDKeyboardModifierMappingDst": 0x7_0000_0000 | UInt64($0.to)]
        }
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        return IOHIDEventSystemClientSetProperty(client, "UserKeyMapping" as CFString, mapping as CFArray)
    }
}

/// Keys offered in the remap pickers, grouped for menus.
public enum KeyCatalog {
    public struct Key: Hashable {
        public let usage: UInt16
        public let name: String
    }

    public static let groups: [(title: String, keys: [Key])] = [
        ("Special", [
            Key(usage: 0x64, name: "§ (left of 1)"),
            Key(usage: 0x35, name: "` (grave)"),
            Key(usage: 0x39, name: "Caps Lock"),
            Key(usage: 0x29, name: "Escape"),
            Key(usage: 0x2B, name: "Tab"),
            Key(usage: 0x28, name: "Return"),
            Key(usage: 0x2C, name: "Space"),
            Key(usage: 0x2A, name: "Delete"),
            Key(usage: 0x4C, name: "Forward Delete"),
        ]),
        ("Modifiers", [
            Key(usage: 0xE0, name: "Left Control"),
            Key(usage: 0xE2, name: "Left Option"),
            Key(usage: 0xE3, name: "Left Command"),
            Key(usage: 0xE1, name: "Left Shift"),
            Key(usage: 0xE4, name: "Right Control"),
            Key(usage: 0xE6, name: "Right Option"),
            Key(usage: 0xE7, name: "Right Command"),
            Key(usage: 0xE5, name: "Right Shift"),
        ]),
        ("Navigation", [
            Key(usage: 0x52, name: "Up Arrow"),
            Key(usage: 0x51, name: "Down Arrow"),
            Key(usage: 0x50, name: "Left Arrow"),
            Key(usage: 0x4F, name: "Right Arrow"),
            Key(usage: 0x4A, name: "Home"),
            Key(usage: 0x4D, name: "End"),
            Key(usage: 0x4B, name: "Page Up"),
            Key(usage: 0x4E, name: "Page Down"),
        ]),
        // F13–F20 exist in macOS but on almost no keyboard: ideal for global shortcuts.
        ("Function keys", run(0x3A, (1...12).map { "F\($0)" }) + run(0x68, (13...20).map { "F\($0)" })),
        ("Letters", run(0x04, "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init))),
        ("Digits", run(0x1E, (1...9).map(String.init)) + run(0x27, ["0"])),
    ]

    /// Consecutive usages starting at `first`.
    private static func run(_ first: UInt16, _ names: [String]) -> [Key] {
        names.enumerated().map { Key(usage: first + UInt16($0.offset), name: $0.element) }
    }

    public static func name(_ usage: UInt16) -> String {
        groups.lazy.flatMap(\.keys).first { $0.usage == usage }?.name ?? String(format: "Key 0x%02X", usage)
    }
}
