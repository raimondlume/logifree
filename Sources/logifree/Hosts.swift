import Foundation

/// `logifree hosts …`: view and manage the Easy-Switch slots of connected devices.
enum Hosts {
    static func run(_ args: [String]) -> Int32 {
        let devices = connectedDevices().filter { $0.has(HIDPP.Feature.changeHost) }
        guard !devices.isEmpty else {
            print("No Easy-Switch devices found. Is the mouse/keyboard awake and connected to this Mac?")
            return 1
        }

        switch args.first {
        case nil, "list":
            for (number, device) in devices.enumerated() { list(device, number: number + 1) }
            return 0
        case "switch" where args.count == 3:
            return withSlot(devices, args) { device, slot, _ in
                try device.notify(HIDPP.Feature.changeHost, 1, [slot])
                print("\(device.name) → slot \(slot + 1)")
            }
        case "rename" where args.count >= 4:
            return withSlot(devices, args) { device, slot, _ in
                try rename(device, slot: slot, to: args[3...].joined(separator: " "))
                print("Renamed \(device.name) slot \(slot + 1)")
            }
        case "forget" where args.count == 3:
            return withSlot(devices, args) { device, slot, current in
                guard slot != current else {
                    print("That's the slot this Mac is connected through; forget it from another host.")
                    return
                }
                let capabilities = try device.call(HIDPP.Feature.hostsInfo, 0)[0]
                guard capabilities & 0x08 != 0 else {
                    print("\(device.name) doesn't support forgetting slots from software.")
                    return
                }
                try device.call(HIDPP.Feature.hostsInfo, 6, [slot])
                print("Forgot \(device.name) slot \(slot + 1)")
            }
        default:
            print(usage)
            return 2
        }
    }

    static let usage = """
        logifree hosts                              list Easy-Switch slots
        logifree hosts switch <device> <slot>       switch a device to another slot
        logifree hosts rename <device> <slot> <name>
        logifree hosts forget <device> <slot>       unpair a slot
        <device>: number from the list, "mouse", "keyboard", or part of its name
        """

    private static func connectedDevices() -> [Device] {
        var transports: [Transport] = []
        let monitor = HIDMonitor()
        monitor.onAttach = { transports.append($0) }
        monitor.start()
        RunLoop.main.run(until: Date() + 0.3) // let attach callbacks arrive
        let devices = transports.flatMap { $0.discoverDevices() }
        devices.forEach { $0.loadIdentity() }
        return devices
    }

    private static func list(_ device: Device, number: Int) {
        print("[\(number)] \(device.name) (\(device.kindName), via \(device.route))")
        guard let info = try? device.call(HIDPP.Feature.changeHost, 0) else { return print("    couldn't read slots") }
        let (count, current) = (info[0], info[1])
        let hostsInfo = device.has(HIDPP.Feature.hostsInfo)
        for slot in 0..<count {
            var name = "", bus = ""
            if hostsInfo, let host = try? device.call(HIDPP.Feature.hostsInfo, 1, [slot]) {
                bus = host[1] == 0 ? "empty"
                    : [1: "eQuad", 2: "USB", 3: "Bluetooth", 4: "Bluetooth", 5: "Bolt"][host[2]] ?? "?"
                name = host[1] == 0 ? "" : friendlyName(device, slot: slot, length: Int(host[4]))
            }
            let marker = slot == current ? "← this Mac" : ""
            print("    \(slot + 1)  \(name.padding(toLength: 24, withPad: " ", startingAt: 0)) \(bus.padding(toLength: 10, withPad: " ", startingAt: 0)) \(marker)")
        }
    }

    private static func friendlyName(_ device: Device, slot: UInt8, length: Int) -> String {
        var bytes: [UInt8] = []
        while bytes.count < length,
              let chunk = try? device.call(HIDPP.Feature.hostsInfo, 3, [slot, UInt8(bytes.count)]) {
            bytes += chunk[2...].prefix(length - bytes.count)
        }
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }

    private static func rename(_ device: Device, slot: UInt8, to name: String) throws {
        let host = try device.call(HIDPP.Feature.hostsInfo, 1, [slot])
        guard host[1] != 0 else { return print("Slot \(slot + 1) is empty.") }
        let maxLength = Int(host[5])
        var bytes: [UInt8] = []
        for character in name where bytes.count + character.utf8.count <= maxLength {
            bytes += character.utf8
        }
        bytes += [UInt8](repeating: 0, count: maxLength - bytes.count)
        for offset in stride(from: 0, to: maxLength, by: 14) {
            let chunk = Array(bytes[offset..<min(offset + 14, maxLength)])
            try device.call(HIDPP.Feature.hostsInfo, 4, [slot, UInt8(offset)] + chunk)
        }
    }

    private static func withSlot(
        _ devices: [Device], _ args: [String], _ body: (Device, UInt8, UInt8) throws -> Void
    ) -> Int32 {
        let query = args[1].lowercased()
        let device = Int(query).flatMap { devices.indices.contains($0 - 1) ? devices[$0 - 1] : nil }
            ?? devices.first { $0.kindName == query }
            ?? devices.first { $0.name.lowercased().contains(query) }
        guard let device else { print("No device matches \"\(args[1])\"."); return 1 }
        guard let info = try? device.call(HIDPP.Feature.changeHost, 0) else { print("Couldn't read slots."); return 1 }
        guard let slot = Int(args[2]), (1...Int(info[0])).contains(slot) else {
            print("Slot must be 1–\(info[0])."); return 1
        }
        do {
            try body(device, UInt8(slot - 1), info[1])
            return 0
        } catch {
            print("Failed: \(error)")
            return 1
        }
    }
}
