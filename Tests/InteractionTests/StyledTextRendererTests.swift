@testable import Interaction
import Testing

struct StyledTextRendererTests {
    @Test("plain rendering strips all styling")
    func plainRenderingStripsAllStyling() {
        let renderer = StyledTextRenderer(colorized: false)
        let text: StyledText = "Run \(StyledText.Segment.command("egg hatch")) in \(StyledText.Segment.path("/tmp"))"

        #expect(renderer.render(text) == "Run 'egg hatch' in /tmp")
    }

    @Test("colorized rendering wraps styled segments in SGR codes")
    func colorizedRenderingWrapsStyledSegmentsInSGRCodes() {
        let renderer = StyledTextRenderer(colorized: true)
        let text: StyledText = "\(StyledText.Segment.success("Added")) file"

        #expect(renderer.render(text) == "\u{1B}[32mAdded\u{1B}[0m file")
    }

    @Test("colorized rendering leaves plain segments untouched")
    func colorizedRenderingLeavesPlainSegmentsUntouched() {
        let renderer = StyledTextRenderer(colorized: true)

        #expect(renderer.render("plain message") == "plain message")
    }

    @Test("colorized rendering matches plain text after stripping escapes")
    func colorizedRenderingMatchesPlainTextAfterStrippingEscapes() {
        let renderer = StyledTextRenderer(colorized: true)
        let text: StyledText = "\(StyledText.Segment.danger("error")): \(StyledText.Segment.muted("details")) \(StyledText.Segment.link(title: "docs", destination: "https://example.com"))"

        #expect(renderer.render(text).withoutANSIEscapeSequences == text.plainText)
    }
}
