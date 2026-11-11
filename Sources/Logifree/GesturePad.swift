import LogifreeCore
import SwiftUI

/// The five gesture mappings, laid out in the direction your hand moves.
struct GesturePad: View {
    @Binding var gestures: [ThumbGesture: Action]

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 14) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                cell(.swipeUp)
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
            GridRow {
                cell(.swipeLeft)
                cell(.click)
                cell(.swipeRight)
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                cell(.swipeDown)
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func cell(_ gesture: ThumbGesture) -> some View {
        GestureCell(gesture: gesture, action: Binding(
            get: { gestures[gesture] },
            set: { gestures[gesture] = $0 }
        ))
    }
}

private struct GestureCell: View {
    let gesture: ThumbGesture
    @Binding var action: Action?

    var body: some View {
        VStack(spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(title, selection: Binding(
                get: { ActionChoice(action) },
                set: { if $0 != ActionChoice(action) { action = $0.action } }
            )) {
                ForEach(ActionChoice.allCases, id: \.self) { choice in
                    Text(choice.title).tag(choice)
                    if choice == .desktopRight { Divider() }
                }
            }
            .labelsHidden()
            .frame(width: 148)
            if case .keystroke(let combo) = action {
                ShortcutRecorder(combo: Binding(get: { combo }, set: { action = .keystroke($0) }))
                    .frame(width: 148)
            }
            if case .shell(let command) = action {
                TextField("open -a Notes", text: Binding(get: { command }, set: { action = .shell($0) }))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 148)
            }
        }
    }

    private var title: String {
        switch gesture {
        case .click: "Click"
        case .swipeUp: "Up"
        case .swipeDown: "Down"
        case .swipeLeft: "Left"
        case .swipeRight: "Right"
        }
    }

    private var symbol: String {
        switch gesture {
        case .click: "circle.circle"
        case .swipeUp: "arrow.up"
        case .swipeDown: "arrow.down"
        case .swipeLeft: "arrow.left"
        case .swipeRight: "arrow.right"
        }
    }
}

private enum ActionChoice: CaseIterable, Hashable {
    case none, missionControl, appExpose, showDesktop, desktopLeft, desktopRight, keystroke, shell

    init(_ action: Action?) {
        switch action {
        case nil: self = .none
        case .missionControl: self = .missionControl
        case .appExpose: self = .appExpose
        case .showDesktop: self = .showDesktop
        case .desktopLeft: self = .desktopLeft
        case .desktopRight: self = .desktopRight
        case .keystroke: self = .keystroke
        case .shell: self = .shell
        }
    }

    var title: String {
        switch self {
        case .none: "Nothing"
        case .missionControl: "Mission Control"
        case .appExpose: "App Exposé"
        case .showDesktop: "Show Desktop"
        case .desktopLeft: "Previous desktop"
        case .desktopRight: "Next desktop"
        case .keystroke: "Keyboard shortcut"
        case .shell: "Shell command"
        }
    }

    var action: Action? {
        switch self {
        case .none: nil
        case .missionControl: .missionControl
        case .appExpose: .appExpose
        case .showDesktop: .showDesktop
        case .desktopLeft: .desktopLeft
        case .desktopRight: .desktopRight
        case .keystroke: .keystroke(.unset)
        case .shell: .shell("")
        }
    }
}
