import Foundation
import LogifreeCore

/// `logifree hosts …`: view and manage the Easy-Switch slots of connected devices.
enum HostsCommand {
    static let usage = """
        logifree hosts                              list Easy-Switch slots
        logifree hosts switch <device> <slot>       switch a device to another slot
        logifree hosts rename <device> <slot> <name>
        logifree hosts forget <device> <slot>       unpair a slot
        <device>: number from the list, "mouse", "keyboard", or part of its name
        """

    static func run(_ args: [String]) -> Int32 {
        let browser = DeviceBrowser()
        RunLoop.main.run(until: Date() + 0.3) // let attach callbacks arrive
        let devices = DeviceBrowser.devices(on: browser.currentTransports).filter(\.hasEasySwitch)
        guard !devices.isEmpty else {
            print("No Easy-Switch devices found. Is the mouse/keyboard awake and connected to this Mac?")
            return 1
        }

        switch args.first {
        case nil, "list":
            for (number, device) in devices.enumerated() { list(device, number: number + 1) }
            return 0
        case "switch" where args.count == 3:
            return withSlot(devices, args) { device, slot in
                try device.switchHost(to: slot.index)
                print("\(device.name) → slot \(slot.index + 1)")
            }
        case "rename" where args.count >= 4:
            return withSlot(devices, args) { device, slot in
                guard slot.paired else { return print("Slot \(slot.index + 1) is empty.") }
                try device.renameHost(slot.index, to: args[3...].joined(separator: " "))
                print("Renamed \(device.name) slot \(slot.index + 1)")
            }
        case "forget" where args.count == 3:
            return withSlot(devices, args) { device, slot in
                guard !slot.isCurrent else {
                    return print("That's the slot this Mac is connected through; forget it from another host.")
                }
                guard device.canForgetHosts else {
                    return print("\(device.name) doesn't support forgetting slots from software.")
                }
                try device.forgetHost(slot.index)
                print("Forgot \(device.name) slot \(slot.index + 1)")
            }
        default:
            print(usage)
            return 2
        }
    }

    private static func list(_ device: Device, number: Int) {
        print("[\(number)] \(device.name) (\(device.kindName), via \(device.route))")
        guard let slots = try? device.hostSlots() else { return print("    couldn't read slots") }
        for slot in slots {
            let name = slot.name.padding(toLength: 24, withPad: " ", startingAt: 0)
            let bus = (slot.paired ? slot.bus : "empty").padding(toLength: 10, withPad: " ", startingAt: 0)
            print("    \(slot.index + 1)  \(name) \(bus) \(slot.isCurrent ? "← this Mac" : "")")
        }
    }

    private static func withSlot(_ devices: [Device], _ args: [String], _ body: (Device, HostSlot) throws -> Void) -> Int32 {
        let query = args[1].lowercased()
        let device = Int(query).flatMap { devices.indices.contains($0 - 1) ? devices[$0 - 1] : nil }
            ?? devices.first { $0.kindName == query }
            ?? devices.first { $0.name.lowercased().contains(query) }
        guard let device else { print("No device matches \"\(args[1])\"."); return 1 }
        guard let slots = try? device.hostSlots() else { print("Couldn't read slots."); return 1 }
        guard let number = Int(args[2]), slots.indices.contains(number - 1) else {
            print("Slot must be 1–\(slots.count)."); return 1
        }
        do {
            try body(device, slots[number - 1])
            return 0
        } catch {
            print("Failed: \(error)")
            return 1
        }
    }
}
