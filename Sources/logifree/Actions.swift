import ApplicationServices
import Foundation

enum Gesture: Hashable {
    case click, swipeUp, swipeDown, swipeLeft, swipeRight
}

enum Action {
    case missionControl
    case appExpose
    case showDesktop
    case desktopLeft
    case desktopRight
    /// A key press, e.g. `.keystroke(key: 0x31, flags: [.maskCommand])` for ⌘Space.
    /// Key codes: the `kVK_*` constants in Carbon's Events.h.
    case keystroke(key: CGKeyCode, flags: CGEventFlags)
    /// Run a shell command, e.g. `.shell("open -a Notes")`.
    case shell(String)

    func perform() {
        switch self {
        case .missionControl: SymbolicHotKey.post(32)
        case .appExpose: SymbolicHotKey.post(33)
        case .showDesktop: SymbolicHotKey.post(36)
        case .desktopLeft: SymbolicHotKey.post(79)
        case .desktopRight: SymbolicHotKey.post(81)
        case .keystroke(let key, let flags): postKey(key, flags)
        case .shell(let command):
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
