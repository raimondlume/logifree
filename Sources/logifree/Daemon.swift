import ApplicationServices
import Foundation

/// Applies `Config` to every Logitech device as it connects, and turns gesture
/// button events into actions. Idle = parked in the run loop; nothing polls.
final class Daemon {
    private let monitor = HIDMonitor()
    private var devices: [Device] = []

    private static let gestureButton: [UInt8] = [0x00, 0xC3]

    func run() -> Never {
        Log.info("logifree started")
        if !Config.gestureButton.isEmpty {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            if !AXIsProcessTrustedWithOptions(options) {
                Log.info("no Accessibility permission yet: gesture actions can't send shortcuts until it's granted")
            }
        }
        monitor.onAttach = { [unowned self] in attach($0) }
        monitor.onDetach = { [unowned self] transport in
            devices.removeAll { $0.transport === transport }
            Log.info("\(transport.productName) disconnected")
        }
        monitor.start()
        CFRunLoopRun()
        exit(0)
    }

    private func attach(_ transport: Transport) {
        Log.info("found \(transport.productName) (\(transport.kind))")
        transport.onNotification = { [unowned self, unowned transport] in notification(transport, $0) }
        for device in transport.discoverDevices() {
            devices.append(device)
            scheduleConfigure(device, after: 0)
        }
    }

    private func device(_ transport: Transport, _ index: UInt8) -> Device? {
        devices.first { $0.transport === transport && $0.index == index }
    }

    private func notification(_ transport: Transport, _ report: [UInt8]) {
        // Receiver: a device (re)connected, e.g. woke from sleep.
        if report[0] == 0x10 && report[2] == 0x41 && transport.kind == .receiver {
            guard report[4] & 0x40 == 0 else { return } // link lost
            let device = device(transport, report[1]) ?? {
                let device = Device(transport: transport, index: report[1])
                devices.append(device)
                return device
            }()
            scheduleConfigure(device, after: 0.5)
            return
        }

        // HID++ 2.0 events from a device carry software ID 0.
        guard report[0] == 0x11, report[3] & 0x0F == 0, let device = device(transport, report[1]) else { return }
        let function = report[3] >> 4
        let params = Array(report.dropFirst(4))

        if report[2] == device.cachedIndex(HIDPP.Feature.wirelessStatus) {
            // Device reconnected and forgot our settings.
            scheduleConfigure(device, after: 0.5)
        } else if report[2] == device.cachedIndex(HIDPP.Feature.reprogControls) {
            if function == 0 { divertedButtons(device, params) }
            if function == 1, device.gestureHeld {
                device.gestureDX += Int(Int16(bitPattern: UInt16(params[0]) << 8 | UInt16(params[1])))
                device.gestureDY += Int(Int16(bitPattern: UInt16(params[2]) << 8 | UInt16(params[3])))
            }
        }
    }

    private func divertedButtons(_ device: Device, _ params: [UInt8]) {
        let pressed = stride(from: 0, to: 8, by: 2).contains { Array(params[$0...$0 + 1]) == Self.gestureButton }
        if pressed && !device.gestureHeld {
            device.gestureHeld = true
            device.gestureDX = 0
            device.gestureDY = 0
        } else if !pressed && device.gestureHeld {
            device.gestureHeld = false
            let (dx, dy) = (device.gestureDX, device.gestureDY)
            let gesture: Gesture =
                max(abs(dx), abs(dy)) < Config.swipeThreshold ? .click
                : abs(dx) > abs(dy) ? (dx < 0 ? .swipeLeft : .swipeRight)
                : (dy < 0 ? .swipeUp : .swipeDown)
            Config.gestureButton[gesture]?.perform()
        }
    }

    /// Debounced: reconnects tend to arrive as a burst of notifications.
    private func scheduleConfigure(_ device: Device, after delay: TimeInterval, attempt: Int = 1) {
        device.configureGeneration += 1
        let generation = device.configureGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak device] in
            guard let self, let device, device.configureGeneration == generation else { return }
            if !configure(device), attempt < 3 {
                scheduleConfigure(device, after: 1, attempt: attempt + 1)
            }
        }
    }

    /// Returns false if the device didn't answer (asleep, mid-reconnect).
    private func configure(_ device: Device) -> Bool {
        device.resetFeatures()
        device.gestureHeld = false
        guard device.ping() else { return false }
        device.loadIdentity()
        _ = device.has(HIDPP.Feature.wirelessStatus) // cache its index to spot reconnects

        var applied: [String] = []
        func attempt(_ label: String, _ body: () throws -> Void) {
            do { try body(); applied.append(label) } catch HIDPPError.unsupported {
            } catch { applied.append("\(label) failed: \(error)") }
        }

        if device.has(HIDPP.Feature.hiresWheel) {
            attempt(Config.invertWheel ? "wheel inverted" : "wheel normal") {
                let mode = try device.call(HIDPP.Feature.hiresWheel, 1) // getWheelMode
                // Bit 0: report via HID++ (no, keep native). Bit 1: hi-res (no, native
                // macOS doesn't understand it). Bit 2: invert. Keep the other bits.
                let flags = mode[0] & ~0x07 | (Config.invertWheel ? 0x04 : 0)
                try device.call(HIDPP.Feature.hiresWheel, 2, [flags, mode[1], mode[2]])
            }
        }
        if device.has(HIDPP.Feature.thumbwheel) {
            attempt(Config.invertThumbwheel ? "thumb wheel inverted" : "thumb wheel normal") {
                try device.call(HIDPP.Feature.thumbwheel, 2, [0, Config.invertThumbwheel ? 1 : 0])
            }
        }
        if device.kind == 3, !Config.gestureButton.isEmpty, device.has(HIDPP.Feature.reprogControls) {
            attempt("gesture button diverted") {
                // setCidReporting: divert (+valid), raw XY (+valid) so swipes can be measured.
                do {
                    try device.call(HIDPP.Feature.reprogControls, 3, Self.gestureButton + [0x33])
                } catch HIDPPError.hidpp20 {
                    try device.call(HIDPP.Feature.reprogControls, 3, Self.gestureButton + [0x03])
                    Log.info("\(device.name): no raw XY on the gesture button, only clicks will work")
                }
            }
        }
        Log.info("\(device.name) (\(device.kindName), \(device.route)): \(applied.isEmpty ? "nothing to do" : applied.joined(separator: ", "))")
        return true
    }
}
