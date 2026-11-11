import Foundation
import os

/// Unified logging (`log stream --predicate 'subsystem == "dev.raimond.logifree"'`),
/// echoed to stdout when run from a terminal.
public enum Log {
    private static let logger = Logger(subsystem: "dev.raimond.logifree", category: ProcessInfo.processInfo.processName)
    private static let echo = isatty(STDOUT_FILENO) != 0 || debugEnabled
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    /// `LOGIFREE_DEBUG=1` prints every HID++ report.
    public static let debugEnabled = ProcessInfo.processInfo.environment["LOGIFREE_DEBUG"] != nil

    public static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        if echo { print("\(formatter.string(from: Date())) \(message)") }
    }

    public static func debug(_ message: @autoclosure () -> String) {
        if debugEnabled { print("\(formatter.string(from: Date())) \(message())") }
    }

    public static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
