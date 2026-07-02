@testable import Interaction
import Testing

struct TableRendererTests {
    @Test func `renders tables using terminal display width`() {
        let table = Table(
            headers: ["name", "description"],
            rows: [
                ["日本語", "wide"],
                ["abc", "latin"],
            ],
        )

        let output = TableRenderer().render(table)

        #expect(output.contains("name   description"))
        #expect(output.contains("日本語 wide"))
        #expect(output.contains("abc    latin"))
    }
}
