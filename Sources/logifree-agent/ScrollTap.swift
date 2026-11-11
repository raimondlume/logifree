import CoreGraphics
import LogifreeCore

/// Makes slow wheel clicks scroll at least `minimumLines`. It edits macOS's own
/// wheel events in place: nothing is synthesized or animated, faster scrolling
/// (already accelerated past the minimum) passes untouched, and so do trackpads
/// and horizontal scrolling. With the minimum at 1 there's no tap at all.
final class ScrollTap {
    private var tap: CFMachPort?

    var minimumLines = 1 {
        didSet { update() }
    }

    private func update() {
        let wanted = minimumLines > 1
        if wanted, tap == nil { create() }
        if let tap { CGEvent.tapEnable(tap: tap, enable: wanted) }
    }

    private func create() {
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
            callback: { _, type, event, context in
                Unmanaged<ScrollTap>.fromOpaque(context!).takeUnretainedValue().handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return Log.info("couldn't watch the scroll wheel: Accessibility permission missing")
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        self.tap = tap
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: minimumLines > 1) }
            return pass
        }
        // Trackpads and Magic Mouse send continuous (pixel) scrolls; wheels send discrete clicks.
        guard type == .scrollWheel, event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else { return pass }

        let lines = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let fixed = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let point = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let minimum = Double(minimumLines)
        Log.debug("scroll in: lines \(lines) fixed \(fixed) point \(point)")
        guard fixed != 0, abs(fixed) < minimum else { return pass }

        let sign: Double = fixed < 0 ? -1 : 1
        let scale = minimum / abs(fixed)
        // Writing the line field makes CoreGraphics recompute the other two, so it goes first.
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(sign * minimum))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: sign * minimum)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: point * scale)
        Log.debug("scroll out: lines \(Int(sign * minimum)) fixed \(sign * minimum) point \(point * scale)")
        return pass
    }
}
