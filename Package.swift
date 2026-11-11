// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "logifree",
    platforms: [.macOS("27.0")],
    targets: [
        // HID++ protocol, device access and the settings file, shared by both executables.
        .target(name: "LogifreeCore"),
        // Headless background agent (launchd) + the `logifree hosts` CLI.
        .executableTarget(name: "logifree-agent", dependencies: ["LogifreeCore"]),
        // Settings window. Opened on demand, quits when closed.
        .executableTarget(name: "Logifree", dependencies: ["LogifreeCore"]),
        .testTarget(name: "LogifreeCoreTests", dependencies: ["LogifreeCore"]),
    ]
)
