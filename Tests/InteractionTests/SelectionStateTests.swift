@testable import Interaction
import Testing

struct SelectionStateTests {
    @Test("single selection clamps cursor when filtering shrinks options")
    func singleSelectionClampsCursorWhenFilteringShrinksOptions() {
        var state = SingleSelectionState(
            options: ["Alpha", "ベータ", "日本語", "Gamma"].map { ChoiceOption($0) },
        )

        state.moveDown()
        state.moveDown()
        state.moveDown()
        state.filter = "日"

        #expect(state.visibleOptions.map(\.value) == ["日本語"])
        #expect(state.cursorIndex == 0)
        #expect(state.selected?.value == "日本語")
    }

    @Test("single selection filters case and diacritic insensitively")
    func singleSelectionFiltersCaseAndDiacriticInsensitively() {
        var state = SingleSelectionState(
            options: ["Café", "CafeKit", "Swift"].map { ChoiceOption($0) },
        )

        state.filter = "cafe"

        #expect(state.visibleOptions.map(\.value) == ["Café", "CafeKit"])
    }

    @Test("multiple selection respects min and max limits")
    func multipleSelectionRespectsMinAndMaxLimits() {
        var state = MultipleSelectionState(
            options: ["one", "two", "three"].map { ChoiceOption($0) },
            minimumSelectionCount: 1,
            maximumSelectionCount: 2,
        )

        state.toggleFocusedOption()
        state.moveDown()
        state.toggleFocusedOption()
        state.moveDown()
        state.toggleFocusedOption()

        #expect(state.selectedValues == ["one", "two"])

        state.moveCursorToBeginning()
        state.toggleFocusedOption()

        #expect(state.selectedValues == ["two"])

        state.toggleFocusedOption()

        #expect(state.selectedValues == ["one", "two"])
    }
}
