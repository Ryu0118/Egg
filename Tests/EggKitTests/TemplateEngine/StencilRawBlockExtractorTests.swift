@testable import EggKit
import Foundation
import Testing

struct StencilRawBlockExtractorTests {
    // MARK: - Extraction

    @Test
    func leavesTemplateWithoutRawTagsUntouched() throws {
        let input = "{{ ___NAME___ }} and ${{ github.sha }}"
        let extraction = try StencilRawBlockExtractor.extract(from: input)

        #expect(extraction.text == input)
        #expect(extraction.blocks.isEmpty)
    }

    @Test
    func hidesRawBodyFromStencilSignificantCharacters() throws {
        let extraction = try StencilRawBlockExtractor.extract(from: "a{% raw %}${{ x }}{% endraw %}b")

        #expect(extraction.blocks.count == 1)
        #expect(extraction.blocks[0].body == "${{ x }}")
        // The text Stencil sees must contain nothing its lexer would treat as a tag.
        #expect(!extraction.text.contains("{{"))
        #expect(!extraction.text.contains("{%"))
        #expect(extraction.text.hasPrefix("a"))
        #expect(extraction.text.hasSuffix("b"))
    }

    @Test
    func padsPlaceholderSoLineNumbersSurvive() throws {
        let input = "1\n{% raw %}\n2\n3\n{% endraw %}\nTAIL"
        let extraction = try StencilRawBlockExtractor.extract(from: input)

        // The raw block spans lines 2-5, so "TAIL" starts on line 6 of the author's file. The
        // rewritten text must put it on line 6 too, or a Stencil syntax error below the block
        // would report a line number the author cannot find.
        let tailStart = try #require(extraction.text.range(of: "TAIL")).lowerBound
        let lineOfTail = extraction.text[..<tailStart].filter(\.isNewline).count + 1
        #expect(lineOfTail == 6)
    }

    // MARK: - Restoration

    @Test
    func restoresEveryOccurrenceOfADuplicatedPlaceholder() throws {
        let extraction = try StencilRawBlockExtractor.extract(from: "{% raw %}${{ x }}{% endraw %}")
        let placeholder = try #require(extraction.blocks.first).placeholder

        // Stencil duplicates a placeholder when it sits inside a {% for %} loop.
        let rendered = "\(placeholder)-\(placeholder)"
        #expect(StencilRawBlockExtractor.restore(in: rendered, blocks: extraction.blocks) == "${{ x }}-${{ x }}")
    }

    @Test
    func restoresNothingWhenStencilDroppedThePlaceholder() throws {
        let extraction = try StencilRawBlockExtractor.extract(from: "{% raw %}${{ x }}{% endraw %}")

        #expect(StencilRawBlockExtractor.restore(in: "only tail", blocks: extraction.blocks) == "only tail")
    }

    @Test
    func roundTripsMultipleBlocksIndependently() throws {
        let input = "{% raw %}A{% endraw %}|{% raw %}B{% endraw %}"
        let extraction = try StencilRawBlockExtractor.extract(from: input)

        #expect(extraction.blocks.map(\.body) == ["A", "B"])
        #expect(StencilRawBlockExtractor.restore(in: extraction.text, blocks: extraction.blocks) == "A|B")
    }

    // MARK: - Errors

    @Test
    func reportsTheOpeningLineOfANestedRawTag() {
        let input = "line1\n{% raw %}\nline3 {% raw %}\n{% endraw %}"

        #expect(throws: StencilRawBlockExtractor.Error.nestedRawTag(line: 3, openedAtLine: 2)) {
            try StencilRawBlockExtractor.extract(from: input)
        }
    }

    @Test
    func reportsTheOpeningLineOfAnUnclosedRawTag() throws {
        let input = "line1\nline2\n{% raw %}body\nmore"

        var thrown: StencilRawBlockExtractor.Error?
        do {
            _ = try StencilRawBlockExtractor.extract(from: input)
        } catch let error as StencilRawBlockExtractor.Error {
            thrown = error
        }

        let error = try #require(thrown)
        #expect(error == .unclosedRawTag(line: 3))
        // The task requires the message to name the line, so pin the rendered text too.
        #expect(error.errorDescription?.contains("line 3") == true)
    }

    @Test
    func reportsTheLineOfAnUnmatchedEndRawTag() {
        #expect(throws: StencilRawBlockExtractor.Error.unmatchedEndRawTag(line: 2)) {
            try StencilRawBlockExtractor.extract(from: "line1\n{% endraw %}")
        }
    }
}
