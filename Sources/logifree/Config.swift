/// Everything you'd want to change lives here. Edit, then run `scripts/install.sh`.
enum Config {
    /// Reverse the main wheel. Done in the mouse firmware, so the trackpad (and
    /// macOS's "natural scrolling" setting) is untouched.
    static let invertWheel = true

    /// Reverse the thumb wheel (horizontal scroll), same mechanism.
    static let invertThumbwheel = true

    /// What the thumb gesture button does. Click = press and release without
    /// moving; swipes = hold the button and move the mouse. Leave the dictionary
    /// empty to not touch the gesture button at all.
    ///
    /// Available actions: see `Action` in Actions.swift, e.g.
    /// `.keystroke(key: 0x31, flags: [.maskCommand])` or `.shell("open -a Notes")`.
    static let gestureButton: [Gesture: Action] = [
        .click: .missionControl,
        .swipeUp: .missionControl,
        .swipeDown: .appExpose,
        .swipeLeft: .desktopLeft,
        .swipeRight: .desktopRight,
    ]

    /// How far (in raw sensor counts) the mouse must move while the gesture
    /// button is held before it counts as a swipe instead of a click.
    static let swipeThreshold = 50
}
