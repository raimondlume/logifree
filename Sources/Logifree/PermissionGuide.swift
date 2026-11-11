import AppKit
import SwiftUI

/// Opens a System Settings privacy list and docks a small panel under its
/// window holding an app's icon, so granting access is one drag into the list
/// instead of + and a file picker.
final class PermissionGuide {
    static let shared = PermissionGuide()

    private var panel: NSPanel?
    private var timer: Timer?

    /// `isGranted` is checked as the user works; the panel closes once it's true,
    /// or when System Settings closes. `tick` runs alongside, e.g. to ask the
    /// agent to re-check its access.
    func show(app: URL, pane: String, isGranted: @escaping () -> Bool, tick: @escaping () -> Void = {}) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
        close()

        let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: GuideView(app: app, name: name) { [weak self] in self?.close() })
        self.panel = panel

        var missingSince: Date?
        var ticks = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            ticks += 1
            if ticks % 4 == 0 { tick() }
            if isGranted() { return close() }
            if let frame = Self.settingsWindowFrame() {
                missingSince = nil
                place(panel, under: frame)
                if !panel.isVisible { panel.orderFrontRegardless() }
            } else {
                // Give System Settings time to open; then treat it as closed.
                if missingSince == nil { missingSince = Date() }
                if Date().timeIntervalSince(missingSince!) > (ticks < 20 ? 5 : 1) { close() }
            }
        }
    }

    func close() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    /// Just below System Settings' window, or over its bottom edge if there's no room.
    private func place(_ panel: NSPanel, under settings: NSRect) {
        let size = panel.frame.size
        let screen = NSScreen.screens.first { $0.frame.intersects(settings) }?.visibleFrame ?? settings
        var origin = NSPoint(x: settings.midX - size.width / 2, y: settings.minY - size.height - 12)
        if origin.y < screen.minY { origin.y = settings.minY + 16 }
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }

    /// System Settings' main window in Cocoa coordinates. Window bounds don't
    /// need Screen Recording access.
    private static func settingsWindowFrame() -> NSRect? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
              let window = windows.first(where: {
                  $0[kCGWindowOwnerName as String] as? String == "System Settings" && $0[kCGWindowLayer as String] as? Int == 0
              }),
              let bounds = window[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds),
              let primary = NSScreen.screens.first
        else { return nil }
        // CoreGraphics measures from the top of the primary screen, Cocoa from its bottom.
        return NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}

private struct GuideView: View {
    let app: URL
    let name: String
    let close: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .frame(width: 48, height: 48)
                .onDrag { NSItemProvider(object: app as NSURL) }
                .help("Drag into the list in System Settings")
            VStack(alignment: .leading, spacing: 2) {
                Text("Drag \(name) into the list above")
                    .font(.headline)
                Text("Then turn on its switch if it's off.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: close) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Close")
        }
        .padding(.horizontal, 16)
        .frame(width: 380, height: 80)
        .glassEffect(in: .rect(cornerRadius: 20))
    }
}
