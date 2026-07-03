import Foundation

/// Selection state for a multiple-choice prompt.
public struct MultipleSelectionState<Value: Equatable & CustomStringConvertible & Sendable>: Equatable, Sendable {
    /// All available options before filtering.
    public let options: [ChoiceOption<Value>]
    /// The minimum number of values the user must select.
    public let minimumSelectionCount: Int
    /// The maximum number of values the user may select.
    public let maximumSelectionCount: Int?

    /// The focused cursor index within `visibleOptions`.
    public private(set) var cursorIndex: Int
    private var selectedIndexes: Set<Int>
    /// The current case-insensitive filter text.
    public var filter: String {
        didSet { clampCursor() }
    }

    public init(
        options: [ChoiceOption<Value>],
        minimumSelectionCount: Int = 0,
        maximumSelectionCount: Int? = nil,
    ) {
        self.options = options
        self.minimumSelectionCount = minimumSelectionCount
        self.maximumSelectionCount = maximumSelectionCount
        filter = ""
        cursorIndex = 0
        selectedIndexes = []
    }

    /// Options matching the current filter.
    public var visibleOptions: [ChoiceOption<Value>] {
        guard !filter.isEmpty else { return options }
        return options.filter { option in
            option.label.localizedStandardContains(filter)
        }
    }

    /// Values selected in their original option order.
    public var selectedValues: [Value] {
        selectedIndexes.sorted().map { options[$0].value }
    }

    /// Moves focus to the previous visible option, wrapping at the beginning.
    public mutating func moveUp() {
        guard !visibleOptions.isEmpty else { return }
        cursorIndex = cursorIndex == 0 ? visibleOptions.count - 1 : cursorIndex - 1
    }

    /// Moves focus to the next visible option, wrapping at the end.
    public mutating func moveDown() {
        guard !visibleOptions.isEmpty else { return }
        cursorIndex = (cursorIndex + 1) % visibleOptions.count
    }

    /// Moves focus to the first visible option.
    public mutating func moveCursorToBeginning() {
        cursorIndex = 0
    }

    /// Toggles the focused option while respecting selection bounds.
    public mutating func toggleFocusedOption() {
        guard let focused = visibleOptions[safe: cursorIndex],
              let originalIndex = options.firstIndex(of: focused) else { return }

        if selectedIndexes.contains(originalIndex) {
            guard selectedIndexes.count > minimumSelectionCount else { return }
            selectedIndexes.remove(originalIndex)
        } else {
            if let maximumSelectionCount, selectedIndexes.count >= maximumSelectionCount {
                return
            }
            selectedIndexes.insert(originalIndex)
        }
    }

    private mutating func clampCursor() {
        guard !visibleOptions.isEmpty else {
            cursorIndex = 0
            return
        }
        cursorIndex = min(max(cursorIndex, 0), visibleOptions.count - 1)
    }
}
