import Foundation

/// One Easy-Switch slot (0-based `index`; shown to people as index + 1).
public struct HostSlot: Hashable, Codable {
    public let index: UInt8
    public let paired: Bool
    public let bus: String
    /// Nil when the device can't say (no `0x1815`, e.g. MX Anywhere 2S).
    public let name: String?
    public let isCurrent: Bool
}

/// Easy-Switch: HID++ `0x1814` (count, current, switch) and `0x1815` (names, rename, forget).
extension Device {
    public var hasEasySwitch: Bool { has(HIDPP.Feature.changeHost) }

    public func hostSlots() throws -> [HostSlot] {
        let info = try call(HIDPP.Feature.changeHost, 0)
        let (count, current) = (info[0], info[1])
        let named = has(HIDPP.Feature.hostsInfo)
        return (0..<count).map { slot in
            guard named, let host = try? call(HIDPP.Feature.hostsInfo, 1, [slot]) else {
                return HostSlot(index: slot, paired: true, bus: "", name: nil, isCurrent: slot == current)
            }
            let paired = host[1] != 0
            return HostSlot(
                index: slot,
                paired: paired,
                bus: paired ? [1: "eQuad", 2: "USB", 3: "Bluetooth", 4: "Bluetooth", 5: "Bolt"][host[2]] ?? "?" : "",
                name: paired ? hostName(slot, length: Int(host[4])) : "",
                isCurrent: slot == current
            )
        }
    }

    /// The device acts on this and leaves without replying.
    public func switchHost(to slot: UInt8) throws {
        try notify(HIDPP.Feature.changeHost, 1, [slot])
    }

    public func renameHost(_ slot: UInt8, to name: String) throws {
        let host = try call(HIDPP.Feature.hostsInfo, 1, [slot])
        let maxLength = Int(host[5])
        // Options+ writes the whole name buffer, zero-padded, 14 bytes per call.
        var bytes: [UInt8] = []
        for character in name where bytes.count + character.utf8.count <= maxLength {
            bytes += character.utf8
        }
        bytes += [UInt8](repeating: 0, count: maxLength - bytes.count)
        for offset in stride(from: 0, to: maxLength, by: 14) {
            let chunk = Array(bytes[offset..<min(offset + 14, maxLength)])
            try call(HIDPP.Feature.hostsInfo, 4, [slot, UInt8(offset)] + chunk)
        }
    }

    public var canForgetHosts: Bool {
        ((try? call(HIDPP.Feature.hostsInfo, 0)[0]) ?? 0) & 0x08 != 0
    }

    public func forgetHost(_ slot: UInt8) throws {
        try call(HIDPP.Feature.hostsInfo, 6, [slot])
    }

    private func hostName(_ slot: UInt8, length: Int) -> String {
        var bytes: [UInt8] = []
        while bytes.count < length, let chunk = try? call(HIDPP.Feature.hostsInfo, 3, [slot, UInt8(bytes.count)]) {
            bytes += chunk[2...].prefix(length - bytes.count)
        }
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}
