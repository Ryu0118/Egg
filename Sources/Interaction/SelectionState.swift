import Foundation

public struct ChoiceOption<Value: Equatable & CustomStringConvertible & Sendable>: Equatable, Sendable {
    public let value: Value
    public let label: String

    public init(_ value: Value, label: String? = nil) {
        self.value = value
        self.label = label ?? value.description
    }
}

public struct SingleSelectionState<Value: Equatable & CustomStringConvertible & Sendable>: Equatable, Sendable {
    public let options: [ChoiceOption<Value>]
    public var filter: String {
        didSet { clampCursor() }
    }

    public private(set) var cursorIndex: Int

    public init(options: [ChoiceOption<Value>], filter: String = "", cursorIndex: Int = 0) {
        self.options = options
        self.filter = filter
        self.cursorIndex = cursorIndex
        clampCursor()
    }

    public var visibleOptions: [ChoiceOption<Value>] {
        guard !filter.isEmpty else { return options }
        return options.filter { option in
            option.label.localizedStandardContains(filter)
        }
    }

    public var selected: ChoiceOption<Value>? {
        guard visibleOptions.indices.contains(cursorIndex) else { return nil }
        return visibleOptions[cursorIndex]
    }

    public mutating func moveUp() {
        guard !visibleOptions.isEmpty else { return }
        cursorIndex = cursorIndex == 0 ? visibleOptions.count - 1 : cursorIndex - 1
    }

    public mutating func moveDown() {
        guard !visibleOptions.isEmpty else { return }
        cursorIndex = (cursorIndex + 1) % visibleOptions.count
    }

    mutating func clampCursor() {
        guard !visibleOptions.isEmpty else {
            cursorIndex = 0
            return
        }
        cursorIndex = min(max(cursorIndex, 0), visibleOptions.count - 1)
    }
}

public struct MultipleSelectionState<Value: Equatable & CustomStringConvertible & Sendable>: Equatable, Sendable {
    public let options: [ChoiceOption<Value>]
    public let minimumSelectionCount: Int
    public let maximumSelectionCount: Int?
    public var filter: String {
        didSet { clampCursor() }
    }

    public private(set) var cursorIndex: Int
    private var selectedIndexes: Set<Int>

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

    public var visibleOptions: [ChoiceOption<Value>] {
        guard !filter.isEmpty else { return options }
        return options.filter { option in
            option.label.localizedStandardContains(filter)
        }
    }

    public var selectedValues: [Value] {
        selectedIndexes.sorted().map { options[$0].value }
    }

    public mutating func moveUp() {
        guard !visibleOptions.isEmpty else { return }
        cursorIndex = cursorIndex == 0 ? visibleOptions.count - 1 : cursorIndex - 1
    }

    public mutating func moveDown() {
        guard !visibleOptions.isEmpty else { return }
        cursorIndex = (cursorIndex + 1) % visibleOptions.count
    }

    public mutating func moveCursorToBeginning() {
        cursorIndex = 0
    }

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

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
