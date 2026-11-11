import ApplicationServices
import Foundation
import LogifreeCore

/// Applies `Settings` to every Logitech device as it connects, and turns gesture
/// button events into actions. Idle = parked in the run loop; nothing polls.
final class Daemon {
    /// A connected device plus the agent's bookkeeping for it.
    private final class Tracked {
        let device: Device
        var gestureHeld = false
        var gestureDX = 0
        var gestureDY = 0
        var configureGeneration = 0
        var configured = false
        var problem: String?
        init(_ device: Device) { self.device = device }
    }

    private let monitor = HIDMonitor()
    private let scrollTap = ScrollTap()
    private var remapsApplied = false
    private var tracked: [Tracked] = []
    private var settings = Settings.load()

    private static let gestureButton: [UInt8] = [0x00, 0xC3]

    func run() -> Never {
        Log.info("logifree agent started")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            Log.info("no Accessibility permission yet: gesture actions can't send shortcuts until it's granted")
        }
        scrollTap.minimumLines = settings.minimumLinesPerClick
        applyKeyRemaps()
        Settings.observeReload { [unowned self] in reload() }
        monitor.onAttach = { [unowned self] in attach($0) }
        monitor.onDetach = { [unowned self] transport in
            tracked.removeAll { $0.device.transport === transport }
            Log.info("\(transport.productName) disconnected")
            writeStatus()
        }
        monitor.start()
        writeStatus()
        CFRunLoopRun()
        exit(0)
    }

    private func reload() {
        settings = Settings.load()
        scrollTap.minimumLines = settings.minimumLinesPerClick // also retries the tap once Accessibility is granted
        applyKeyRemaps()
        Log.info("settings reloaded")
        tracked.forEach { scheduleConfigure($0, after: 0) }
        writeStatus()
    }

    private func writeStatus() {
        let devices = tracked.filter(\.configured).map { AgentStatus.DeviceState(name: $0.device.name, problem: $0.problem) }
        AgentStatus(accessibility: AXIsProcessTrusted(), devices: devices).save()
    }

    /// Leaves the system's remaps alone unless we have some (or had, and need to clear them).
    private func applyKeyRemaps() {
        guard !settings.keyRemaps.isEmpty || remapsApplied else { return }
        let ok = KeyRemap.apply(settings.keyRemaps)
        remapsApplied = !settings.keyRemaps.isEmpty
        let summary = settings.keyRemaps.map { "\(KeyCatalog.name($0.from)) → \(KeyCatalog.name($0.to))" }
        Log.info(ok ? "key remaps: \(summary.isEmpty ? "cleared" : summary.joined(separator: ", "))" : "couldn't set key remaps")
    }

    private func attach(_ transport: Transport) {
        Log.info("found \(transport.productName) (\(transport.kind))")
        applyKeyRemaps() // a keyboard may have just (re)connected
        transport.onNotification = { [unowned self, unowned transport] in notification(transport, $0) }
        for device in transport.discoverDevices() {
            let entry = Tracked(device)
            tracked.append(entry)
            scheduleConfigure(entry, after: 0)
        }
    }

    private func entry(_ transport: Transport, _ index: UInt8) -> Tracked? {
        tracked.first { $0.device.transport === transport && $0.device.index == index }
    }

    private func notification(_ transport: Transport, _ report: [UInt8]) {
        // Receiver: a device (re)connected, e.g. woke from sleep.
        if report[0] == 0x10 && report[2] == 0x41 && transport.kind == .receiver {
            guard report[4] & 0x40 == 0 else { return } // link lost
            let entry = entry(transport, report[1]) ?? {
                let entry = Tracked(Device(transport: transport, index: report[1]))
                tracked.append(entry)
                return entry
            }()
            scheduleConfigure(entry, after: 0.5)
            return
        }

        // HID++ 2.0 events from a device carry software ID 0.
        guard report[0] == 0x11, report[3] & 0x0F == 0, let entry = entry(transport, report[1]) else { return }
        let function = report[3] >> 4
        let params = Array(report.dropFirst(4))

        if report[2] == entry.device.cachedIndex(HIDPP.Feature.wirelessStatus) {
            // Device reconnected and forgot our settings.
            scheduleConfigure(entry, after: 0.5)
        } else if report[2] == entry.device.cachedIndex(HIDPP.Feature.reprogControls) {
            if function == 0 { divertedButtons(entry, params) }
            if function == 1, entry.gestureHeld {
                entry.gestureDX += Int(Int16(bitPattern: UInt16(params[0]) << 8 | UInt16(params[1])))
                entry.gestureDY += Int(Int16(bitPattern: UInt16(params[2]) << 8 | UInt16(params[3])))
            }
        }
    }

    private func divertedButtons(_ entry: Tracked, _ params: [UInt8]) {
        let pressed = stride(from: 0, to: 8, by: 2).contains { Array(params[$0...$0 + 1]) == Self.gestureButton }
        if pressed && !entry.gestureHeld {
            entry.gestureHeld = true
            entry.gestureDX = 0
            entry.gestureDY = 0
        } else if !pressed && entry.gestureHeld {
            entry.gestureHeld = false
            let gesture = ThumbGesture.classify(dx: entry.gestureDX, dy: entry.gestureDY, threshold: settings.swipeThreshold)
            settings.gestures[gesture]?.perform()
        }
    }

    /// Debounced: reconnects tend to arrive as a burst of notifications.
    private func scheduleConfigure(_ entry: Tracked, after delay: TimeInterval, attempt: Int = 1) {
        entry.configureGeneration += 1
        let generation = entry.configureGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak entry] in
            guard let self, let entry, entry.configureGeneration == generation else { return }
            if configure(entry) {
                writeStatus()
            } else if attempt < 3 {
                scheduleConfigure(entry, after: 1, attempt: attempt + 1)
            }
        }
    }

    /// Returns false if the device didn't answer (asleep, mid-reconnect).
    private func configure(_ entry: Tracked) -> Bool {
        let device = entry.device
        device.resetFeatures()
        entry.gestureHeld = false
        guard device.ping() else { return false }
        device.loadIdentity()
        _ = device.has(HIDPP.Feature.wirelessStatus) // cache its index to spot reconnects

        var applied: [String] = []
        var problems: [String] = []
        func attempt(_ label: String, _ body: () throws -> Void) {
            do { try body(); applied.append(label) } catch HIDPPError.unsupported {
            } catch { problems.append("\(label) failed: \(error)") }
        }

        if device.has(HIDPP.Feature.hiresWheel) {
            attempt(settings.invertWheel ? "wheel inverted" : "wheel normal") {
                let mode = try device.call(HIDPP.Feature.hiresWheel, 1) // getWheelMode
                // Bit 0: report via HID++ (no, keep native). Bit 1: hi-res (no, native
                // macOS doesn't understand it). Bit 2: invert. Keep the other bits.
                let flags = mode[0] & ~0x07 | (settings.invertWheel ? 0x04 : 0)
                try device.call(HIDPP.Feature.hiresWheel, 2, [flags, mode[1], mode[2]])
            }
        }
        if device.has(HIDPP.Feature.thumbwheel) {
            attempt(settings.invertThumbwheel ? "thumb wheel inverted" : "thumb wheel normal") {
                try device.call(HIDPP.Feature.thumbwheel, 2, [0, settings.invertThumbwheel ? 1 : 0])
            }
        }
        if device.isMouse, device.has(HIDPP.Feature.reprogControls) {
            let divert = settings.gestures.values.contains { $0 != .keystroke(.unset) && $0 != .shell("") }
            attempt(divert ? "gesture button diverted" : "gesture button native") {
                // setCidReporting flags: divert (bit 0, valid bit 1), raw XY (bit 4, valid
                // bit 5) so swipes can be measured. Undiverting = valid bits, values 0.
                do {
                    try device.call(HIDPP.Feature.reprogControls, 3, Self.gestureButton + [divert ? 0x33 : 0x22])
                } catch HIDPPError.hidpp20 where divert {
                    try device.call(HIDPP.Feature.reprogControls, 3, Self.gestureButton + [0x03])
                    Log.info("\(device.name): no raw XY on the gesture button, only clicks will work")
                }
            }
        }
        entry.configured = true
        entry.problem = problems.isEmpty ? nil : problems.joined(separator: "; ")
        let summary = (applied + problems).joined(separator: ", ")
        Log.info("\(device.name) (\(device.kindName), \(device.route)): \(summary.isEmpty ? "nothing to do" : summary)")
        return true
    }
}
