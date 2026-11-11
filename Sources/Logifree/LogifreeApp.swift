import SwiftUI

@main
struct LogifreeApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Window("Logifree", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Settings window only: closing it quits, so nothing lingers in memory.
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }
}
