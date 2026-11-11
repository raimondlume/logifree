// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "logifree",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "logifree", path: "Sources/logifree")
    ]
)
