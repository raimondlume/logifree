import Foundation
import IOKit.hid

/// Logitech HID++ framing. Long reports are 20 bytes:
/// `[0x11, deviceIndex, featureIndex, function << 4 | softwareID, params × 16]`.
/// Short (HID++ 1.0, receiver registers) are 7 bytes with report ID 0x10.
public enum HIDPP {
    /// Tags our requests so replies to other software (or another logifree
    /// process) aren't mistaken for ours. Events from the device carry 0.
    /// Agent 0x0A, CLI 0x0B, app 0x0C.
    public static var softwareID: UInt8 = 0x0A

    public enum Feature {
        public static let root: UInt16 = 0x0000
        public static let deviceName: UInt16 = 0x0005
        public static let changeHost: UInt16 = 0x1814
        public static let hostsInfo: UInt16 = 0x1815
        public static let reprogControls: UInt16 = 0x1B04
        public static let wirelessStatus: UInt16 = 0x1D4B
        public static let hiresWheel: UInt16 = 0x2121
        public static let thumbwheel: UInt16 = 0x2150
    }

    public static func isReply(_ reply: [UInt8], to request: [UInt8]) -> Bool {
        guard reply.count >= 5, request.count >= 4, reply[1] == request[1] else { return false }
        if reply[2] == request[2] && reply[3] == request[3] { return true }
        // Error replies (0x8F = HID++ 1.0, 0xFF = HID++ 2.0) echo the request's bytes 2–3.
        return (reply[2] == 0x8F || reply[2] == 0xFF) && reply[3] == request[2] && reply[4] == request[3]
    }

    public static func long(_ index: UInt8, _ featureIndex: UInt8, _ function: UInt8, _ params: [UInt8]) -> [UInt8] {
        let report = [0x11, index, featureIndex, function << 4 | softwareID] + params.prefix(16)
        return report + [UInt8](repeating: 0, count: 20 - report.count)
    }
}

public enum HIDPPError: Error, CustomStringConvertible {
    case timeout
    case sendFailed(Int32)
    case hidpp10(UInt8)
    case hidpp20(UInt8)
    case unsupported(UInt16)

    public var description: String {
        switch self {
        case .timeout: "no reply"
        case .sendFailed(let code): String(format: "send failed (0x%08x)", code)
        case .hidpp10(let code): "receiver error \(code)"
        case .hidpp20(let code):
            [1: "unknown", 2: "invalid argument", 3: "out of range", 4: "hardware error", 5: "internal",
             6: "invalid feature", 7: "invalid function", 8: "busy", 9: "unsupported"][code]
                ?? "device error \(code)"
        case .unsupported(let feature): String(format: "feature 0x%04X not supported", feature)
        }
    }
}

/// A mouse or keyboard reachable through a transport: a receiver slot (1–6) or,
/// over Bluetooth, index 0xFF.
public final class Device {
    public let transport: Transport
    public let index: UInt8
    public private(set) var name = "Unknown device"
    public private(set) var kind: UInt8 = 0xFF // 0x0005 device type: 0 keyboard, 3 mouse, …
    private var features: [UInt16: UInt8] = [:] // 0 = unsupported

    public init(transport: Transport, index: UInt8) {
        self.transport = transport
        self.index = index
    }

    public var isMouse: Bool { kind == 3 }

    public var kindName: String {
        switch kind {
        case 0: "keyboard"
        case 3: "mouse"
        case 4: "trackpad"
        case 5: "trackball"
        default: "device"
        }
    }

    public var route: String {
        transport.kind == .bluetooth ? "Bluetooth" : "\(transport.productName) slot \(index)"
    }

    /// Whether something answers at this index. Absent slots error immediately;
    /// a dozing device can take about a second to wake up and reply.
    public func ping() -> Bool {
        let reply = try? transport.request(HIDPP.long(index, 0, 1, [0, 0, 0x5A]), timeout: 2)
        return reply?[6] == 0x5A
    }

    public func resetFeatures() { features = [:] }

    /// The feature's index on this device, or nil when the device lacks it.
    public func featureIndex(_ feature: UInt16) throws -> UInt8? {
        if feature == HIDPP.Feature.root { return 0 }
        if let cached = features[feature] { return cached == 0 ? nil : cached }
        let reply = try transport.request(HIDPP.long(index, 0, 0, [UInt8(feature >> 8), UInt8(feature & 0xFF)]))
        features[feature] = reply[4]
        return reply[4] == 0 ? nil : reply[4]
    }

    /// The index if already looked up; used to classify incoming events cheaply.
    public func cachedIndex(_ feature: UInt16) -> UInt8? {
        features[feature].flatMap { $0 == 0 ? nil : $0 }
    }

    public func has(_ feature: UInt16) -> Bool { (try? featureIndex(feature)) != nil }

    /// Call a feature function; returns the 16 parameter bytes of the reply.
    @discardableResult
    public func call(_ feature: UInt16, _ function: UInt8, _ params: [UInt8] = []) throws -> [UInt8] {
        guard let featureIndex = try featureIndex(feature) else { throw HIDPPError.unsupported(feature) }
        return Array(try transport.request(HIDPP.long(index, featureIndex, function, params)).dropFirst(4))
    }

    /// Call a function the device acts on without replying (e.g. switching host).
    public func notify(_ feature: UInt16, _ function: UInt8, _ params: [UInt8] = []) throws {
        guard let featureIndex = try featureIndex(feature) else { throw HIDPPError.unsupported(feature) }
        try transport.send(HIDPP.long(index, featureIndex, function, params))
    }

    public func loadIdentity() {
        guard has(HIDPP.Feature.deviceName) else { return }
        if let length = try? call(HIDPP.Feature.deviceName, 0)[0] {
            var bytes: [UInt8] = []
            while bytes.count < Int(length), let chunk = try? call(HIDPP.Feature.deviceName, 1, [UInt8(bytes.count)]) {
                bytes += chunk.prefix(Int(length) - bytes.count)
            }
            name = String(decoding: bytes, as: UTF8.self)
        }
        if let type = try? call(HIDPP.Feature.deviceName, 2)[0] { kind = type }
    }
}

extension Transport {
    /// Find the devices behind this transport that are awake right now.
    public func discoverDevices() -> [Device] {
        switch kind {
        case .bluetooth:
            return [Device(transport: self, index: 0xFF)]
        case .receiver:
            // Ask the receiver to report device (dis)connections, so we notice wake-ups.
            _ = try? request([0x10, 0xFF, 0x80, 0x00, 0x00, 0x09, 0x00], timeout: 0.5)
            return (1...6).map { Device(transport: self, index: $0) }.filter { $0.ping() }
        }
    }
}

/// Device discovery for the CLI and the settings app.
public final class DeviceBrowser {
    private let monitor = HIDMonitor()
    private var transports: [Transport] = []

    public var openResult: IOReturn { monitor.openResult }

    /// Called on main when a receiver or Bluetooth device appears or goes away.
    public var onChange: (() -> Void)?
    /// Called on main with every unsolicited report (device events, receiver
    /// connection notices), for callers that want to react live.
    public var onReport: ((Transport, [UInt8]) -> Void)?

    /// Call on main. Transports show up a moment later, as the main queue runs.
    public init() {
        monitor.onAttach = { [unowned self] transport in
            transports.append(transport)
            transport.onNotification = { [unowned self, unowned transport] in onReport?(transport, $0) }
            onChange?()
        }
        monitor.onDetach = { [unowned self] transport in
            transports.removeAll { $0 === transport }
            onChange?()
        }
        monitor.start()
    }

    /// The transports currently attached. Read on main.
    public var currentTransports: [Transport] { transports }

    /// Blocking (pings each receiver slot); run off main in UI code.
    public static func devices(on transports: [Transport]) -> [Device] {
        let devices = transports.flatMap { $0.discoverDevices() }
        devices.forEach { $0.loadIdentity() }
        return devices
    }
}
