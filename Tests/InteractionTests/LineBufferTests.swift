@testable import Interaction
import Testing

struct LineBufferTests {
    @Test func `inserts and deletes Japanese text by grapheme cluster`() {
        var buffer = LineBuffer()

        buffer.insert("日本語")
        #expect(buffer.text == "日本語")
        #expect(buffer.cursorOffset == 3)
        #expect(buffer.cursorDisplayColumn == 6)

        buffer.moveCursorLeft()
        buffer.backspace()

        #expect(buffer.text == "日語")
        #expect(buffer.cursorOffset == 1)
        #expect(buffer.cursorDisplayColumn == 2)
    }

    @Test func `keeps composed characters intact while editing`() {
        var buffer = LineBuffer("Cafe\u{301}")

        #expect(buffer.text == "Cafe\u{301}")
        #expect(buffer.cursorOffset == 4)
        #expect(buffer.cursorDisplayColumn == 4)

        buffer.backspace()

        #expect(buffer.text == "Caf")
        #expect(buffer.cursorOffset == 3)
        #expect(buffer.cursorDisplayColumn == 3)
    }

    @Test func `treats emoji sequences as one editable unit`() {
        var buffer = LineBuffer("A👨‍👩‍👧‍👦B")

        #expect(buffer.cursorOffset == 3)
        #expect(buffer.cursorDisplayColumn == 4)

        buffer.moveCursorLeft()
        buffer.backspace()

        #expect(buffer.text == "AB")
        #expect(buffer.cursorOffset == 1)
        #expect(buffer.cursorDisplayColumn == 1)
    }

    @Test func `deletes at cursor without crossing character boundaries`() {
        var buffer = LineBuffer("あb👍🏽c")

        buffer.moveCursorToBeginning()
        buffer.moveCursorRight()
        buffer.moveCursorRight()
        buffer.delete()

        #expect(buffer.text == "あbc")
        #expect(buffer.cursorOffset == 2)
        #expect(buffer.cursorDisplayColumn == 3)
    }

    @Test func `supports replacing the current line`() {
        var buffer = LineBuffer("old")

        buffer.replace(with: "新しい value")

        #expect(buffer.text == "新しい value")
        #expect(buffer.cursorOffset == 9)
        #expect(buffer.cursorDisplayColumn == 12)
    }
}
