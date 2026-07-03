@testable import Interaction
import Testing

struct StyledTextRendererTests {
    @Test func `plain rendering strips all styling`() {
        let renderer = StyledTextRenderer(colorized: false)
        let text: StyledText = "Run \(StyledText.Segment.command("egg hatch")) in \(StyledText.Segment.path("/tmp"))"

        #expect(renderer.render(text) == "Run 'egg hatch' in /tmp")
    }

    @Test func `colorized rendering wraps styled segments in SGR codes`() {
        let renderer = StyledTextRenderer(colorized: true)
        let text: StyledText = "\(StyledText.Segment.success("Added")) file"

        #expect(renderer.render(text) == "\u{1B}[32mAdded\u{1B}[0m file")
    }

    @Test func `colorized rendering leaves plain segments untouched`() {
        let renderer = StyledTextRenderer(colorized: true)

        #expect(renderer.render("plain message") == "plain message")
    }

    @Test func `colorized rendering matches plain text after stripping escapes`() {
        let renderer = StyledTextRenderer(colorized: true)
        let text: StyledText = "\(StyledText.Segment.danger("error")): \(StyledText.Segment.muted("details")) \(StyledText.Segment.link(title: "docs", destination: "https://example.com"))"

        #expect(renderer.render(text).withoutANSIEscapeSequences == text.plainText)
    }
}
