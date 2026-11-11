import AppKit
import LogifreeCore
import SwiftUI

/// Click, then press a key combo. Esc cancels.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo
    @State private var monitor: Any?

    var body: some View {
        Button(label) { monitor == nil ? start() : stop() }
            .help(monitor == nil ? "Click, then press the keys" : "Press Esc to cancel")
            .onDisappear { stop() }
    }

    private var label: String {
        if monitor != nil { return "Press a shortcut…" }
        return combo.key == nil ? "Record shortcut" : combo.display
    }

    private func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode != 53 { // Esc
                let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
                combo = KeyCombo(
                    key: event.keyCode,
                    modifiers: UInt64(modifiers.rawValue),
                    display: Self.symbols(modifiers) + Self.keyName(event)
                )
            }
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func symbols(_ flags: NSEvent.ModifierFlags) -> String {
        [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { flags.contains($0.0) }.map(\.1).joined()
    }

    private static let specialKeys: [UInt16: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    private static func keyName(_ event: NSEvent) -> String {
        specialKeys[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "key \(event.keyCode)"
    }
}
