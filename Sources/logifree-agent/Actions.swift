import ApplicationServices
import Foundation
import LogifreeCore

extension Action {
    func perform() {
        switch self {
        case .missionControl: SymbolicHotKey.post(32)
        case .appExpose: SymbolicHotKey.post(33)
        case .showDesktop: SymbolicHotKey.post(36)
        case .desktopLeft: SymbolicHotKey.post(79)
        case .desktopRight: SymbolicHotKey.post(81)
        case .middleClick: postMiddleClick()
        case .keystroke(let combo):
            guard let key = combo.key else { return }
            postKey(CGKeyCode(key), CGEventFlags(rawValue: combo.modifiers))
        case .shell(let command):
            guard !command.isEmpty else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            try? process.run()
        }
    }
}

private let eventSource = CGEventSource(stateID: .hidSystemState)

private func postKey(_ key: CGKeyCode, _ flags: CGEventFlags) {
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: key, keyDown: down) else { return }
        event.flags = flags
        event.post(tap: .cgSessionEventTap)
    }
}

/// At the pointer, as if the middle button had been clicked natively.
private func postMiddleClick() {
    guard let location = CGEvent(source: nil)?.location else { return }
    for type in [CGEventType.otherMouseDown, .otherMouseUp] {
        CGEvent(mouseEventSource: eventSource, mouseType: type, mouseCursorPosition: location, mouseButton: .center)?
            .post(tap: .cgSessionEventTap)
    }
}

/// Triggers macOS's own shortcuts (Mission Control, move a space, …) by posting
/// the exact key combo the system has bound to them, enabling the binding for an
/// instant if it's switched off. Same trick as v3rm0n/logid (MIT) and Mouser.
private enum SymbolicHotKey {
    private typealias GetValue = @convention(c) (
        UInt32, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt32>
    ) -> Int32
    private typealias IsEnabled = @convention(c) (UInt32) -> Bool
    private typealias SetEnabled = @convention(c) (UInt32, Bool) -> Int32

    private static let handle = dlopen(
        "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)

    private static func symbol<T>(_ name: String, _: T.Type) -> T? {
        guard let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    private static let getValue = symbol("CGSGetSymbolicHotKeyValue", GetValue.self)
    private static let isEnabled = symbol("CGSIsSymbolicHotKeyEnabled", IsEnabled.self)
    private static let setEnabled = symbol("CGSSetSymbolicHotKeyEnabled", SetEnabled.self)

    // The enable → post → restore dance sleeps briefly; keep it off the main thread.
    private static let queue = DispatchQueue(label: "hotkeys")

    static func post(_ hotkey: UInt32) {
        queue.async {
            guard let getValue, let isEnabled, let setEnabled else {
                return Log.info("symbolic hotkey API unavailable")
            }
            var character: UInt16 = 0, key: UInt16 = 0, modifiers: UInt32 = 0
            guard getValue(hotkey, &character, &key, &modifiers) == 0 else {
                return Log.info("no key combo bound to system shortcut \(hotkey)")
            }
            let wasEnabled = isEnabled(hotkey)
            if !wasEnabled { _ = setEnabled(hotkey, true) }
            postKey(CGKeyCode(key), CGEventFlags(rawValue: UInt64(modifiers)))
            Thread.sleep(forTimeInterval: 0.05) // let WindowServer act before restoring
            if !wasEnabled { _ = setEnabled(hotkey, false) }
        }
    }
}
