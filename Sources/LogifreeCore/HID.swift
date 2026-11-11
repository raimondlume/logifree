import Foundation
import IOKit.hid

/// One HID++ endpoint macOS exposes: a Bolt/Unifying receiver (talks to up to six
/// devices by slot) or a device connected directly over Bluetooth.
///
/// Input reports arrive on the HID thread. A reply to the in-flight request wakes
/// the waiting caller; everything else is handed to `onNotification` on main.
public final class Transport {
    public enum Kind { case receiver, bluetooth }

    public let device: IOHIDDevice
    public let kind: Kind
    public let productName: String
    /// Set on main; called on main with every report that isn't a reply.
    public var onNotification: (([UInt8]) -> Void)?

    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private let lock = NSLock()
    private var pending: Pending?

    private final class Pending {
        let request: [UInt8]
        let done = DispatchSemaphore(value: 0)
        var reply: [UInt8]?
        init(_ request: [UInt8]) { self.request = request }
    }

    init(device: IOHIDDevice, kind: Kind) {
        self.device = device
        self.kind = kind
        productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "?"
        IOHIDDeviceRegisterInputReportCallback(
            device, buffer, 64,
            { context, _, _, _, reportID, report, length in
                let transport = Unmanaged<Transport>.fromOpaque(context!).takeUnretainedValue()
                var bytes = Array(UnsafeBufferPointer(start: report, count: length))
                if bytes.first != UInt8(truncatingIfNeeded: reportID) {
                    bytes.insert(UInt8(truncatingIfNeeded: reportID), at: 0)
                }
                transport.received(bytes)
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    deinit { buffer.deallocate() }

    private func received(_ report: [UInt8]) {
        Log.debug("<- \(Log.hex(report))")
        guard report.count >= 7 else { return }
        lock.lock()
        if let pending, pending.reply == nil, HIDPP.isReply(report, to: pending.request) {
            pending.reply = report
            lock.unlock()
            pending.done.signal()
            return
        }
        lock.unlock()
        DispatchQueue.main.async { self.onNotification?(report) }
    }

    /// Send a report without waiting for an answer. The first byte is the report ID.
    public func send(_ report: [UInt8]) throws {
        Log.debug("-> \(Log.hex(report))")
        let result = report.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(report[0]), $0.baseAddress!, $0.count)
        }
        guard result == kIOReturnSuccess else { throw HIDPPError.sendFailed(result) }
    }

    /// Send a request and block until its reply (or an error reply) arrives.
    /// Call from one thread at a time; never from the HID thread.
    public func request(_ report: [UInt8], timeout: TimeInterval = 2) throws -> [UInt8] {
        let pending = Pending(report)
        lock.lock(); self.pending = pending; lock.unlock()
        defer { lock.lock(); self.pending = nil; lock.unlock() }

        try send(report)
        guard pending.done.wait(timeout: .now() + timeout) == .success else { throw HIDPPError.timeout }
        lock.lock(); let reply = pending.reply!; lock.unlock()

        if reply[2] == 0x8F { throw HIDPPError.hidpp10(reply[5]) }
        if reply[2] == 0xFF { throw HIDPPError.hidpp20(reply[5]) }
        return reply
    }
}

/// Watches for Logitech HID++ endpoints on a dedicated thread, so replies keep
/// flowing while the caller blocks on a request.
public final class HIDMonitor {
    /// Called on main.
    public var onAttach: ((Transport) -> Void)?
    public var onDetach: ((Transport) -> Void)?
    /// Result of opening the HID manager; `kIOReturnNotPermitted` means Input Monitoring is missing.
    public private(set) var openResult: IOReturn = kIOReturnSuccess

    private var transports: [Transport] = [] // HID thread only

    public init() {}

    public func start() {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            let matching: [[String: Any]] = [
                [kIOHIDVendorIDKey: 0x046D, kIOHIDDeviceUsagePageKey: 0xFF00], // receivers
                [kIOHIDVendorIDKey: 0x046D, kIOHIDDeviceUsagePageKey: 0xFF43], // Bluetooth devices
            ]
            IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
                Unmanaged<HIDMonitor>.fromOpaque(context!).takeUnretainedValue().matched(device)
            }, context)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
                Unmanaged<HIDMonitor>.fromOpaque(context!).takeUnretainedValue().removed(device)
            }, context)

            IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            if openResult != kIOReturnSuccess {
                Log.info("could not open HID devices (\(String(format: "0x%08x", openResult))); check Input Monitoring permission")
                if openResult == kIOReturnNotPermitted { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
            }
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "hid"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
    }

    private func matched(_ device: IOHIDDevice) {
        guard !transports.contains(where: { $0.device === device }) else { return }
        let page = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
        let pairs = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Int]] ?? []
        let pages = Set(pairs.compactMap { $0[kIOHIDDeviceUsagePageKey] } + [page])
        let transport = Transport(device: device, kind: pages.contains(0xFF43) ? .bluetooth : .receiver)
        Log.debug("matched \(transport.productName) \(transport.kind) usage pairs \(pairs)")
        transports.append(transport)
        DispatchQueue.main.async { self.onAttach?(transport) }
    }

    private func removed(_ device: IOHIDDevice) {
        guard let index = transports.firstIndex(where: { $0.device === device }) else { return }
        let transport = transports.remove(at: index)
        DispatchQueue.main.async { self.onDetach?(transport) }
    }
}
