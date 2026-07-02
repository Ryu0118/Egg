public struct LineBuffer: Equatable, Sendable {
    private var characters: [Character]

    public private(set) var cursorOffset: Int

    public init(_ text: String = "") {
        characters = Array(text)
        cursorOffset = characters.count
    }

    public var text: String {
        String(characters)
    }

    public var cursorDisplayColumn: Int {
        String(characters.prefix(cursorOffset)).terminalDisplayWidth
    }

    public mutating func replace(with text: String) {
        characters = Array(text)
        cursorOffset = characters.count
    }

    public mutating func insert(_ text: String) {
        let inserted = Array(text)
        characters.insert(contentsOf: inserted, at: cursorOffset)
        cursorOffset += inserted.count
    }

    public mutating func backspace() {
        guard cursorOffset > 0 else { return }
        cursorOffset -= 1
        characters.remove(at: cursorOffset)
    }

    public mutating func delete() {
        guard cursorOffset < characters.count else { return }
        characters.remove(at: cursorOffset)
    }

    public mutating func moveCursorLeft() {
        cursorOffset = max(0, cursorOffset - 1)
    }

    public mutating func moveCursorRight() {
        cursorOffset = min(characters.count, cursorOffset + 1)
    }

    public mutating func moveCursorToBeginning() {
        cursorOffset = 0
    }

    public mutating func moveCursorToEnd() {
        cursorOffset = characters.count
    }
}
