@testable import Interaction
import Testing

@Suite("Builds and renders tables with column alignment based on terminal display width")
struct TableRendererTests {
    @Test(
        "keeps every rendered line (borders, header, and every row) at the exact same terminal display width, regardless of character class",
        arguments: MixedWidthFixture.allCases,
    )
    func keepsUniformLineWidthAcrossCharacterClasses(_ fixture: MixedWidthFixture) {
        let output = TableRenderer().render(fixture.table)
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let widths = lines.map(\.terminalDisplayWidth)

        #expect(
            Set(widths).count == 1,
            "expected every line to share one display width, got \(widths) for:\n\(output)",
        )
    }

    /// A table exercising a distinct terminal-width edge case, paired with the
    /// same-width invariant every rendered line must satisfy regardless of it.
    struct MixedWidthFixture: CustomTestStringConvertible {
        let description: String
        let table: Table

        static let allCases: [Self] = [
            Self(description: "ASCII only", table: Table(
                headers: ["name", "count"],
                rows: [["alpha", "1"], ["beta", "22"]],
            )),
            Self(description: "CJK mixed with ASCII in the same column", table: Table(
                headers: ["name", "note"],
                rows: [["日本語", "wide"], ["한글", "korean"], ["abc", "latin"]],
            )),
            Self(description: "emoji ZWJ family sequence and flag sequence", table: Table(
                headers: ["emoji", "label"],
                rows: [["👨‍👩‍👧‍👦", "family"], ["🇯🇵", "flag"], ["👍🏽", "modifier"]],
            )),
            Self(description: "composed accents and combining marks", table: Table(
                headers: ["name", "note"],
                rows: [["e\u{301}", "combining"], ["café", "precomposed"]],
            )),
            Self(description: "wide characters in the header itself", table: Table(
                headers: ["名前", "説明"],
                rows: [["abc", "latin"], ["中文", "chinese"]],
            )),
            Self(description: "a row shorter than the header padded with an empty cell", table: Table(
                headers: ["name", "description"],
                rows: [["日本語"], ["abc", "latin"]],
            )),
            Self(description: "empty string cells alongside wide content", table: Table(
                headers: ["name", "note"],
                rows: [["", ""], ["日本語", ""], ["", "note"]],
            )),
            Self(description: "no header, only mixed-width rows", table: Table(
                headers: [],
                rows: [["日本語", "1"], ["a", "🇯🇵"]],
            )),
        ]

        var testDescription: String {
            description
        }
    }

    @Test("renders a box-drawn table with wide Japanese cells so columns align using display width rather than character count")
    func rendersTablesUsingTerminalDisplayWidth() {
        let table = Table(
            headers: ["name", "description"],
            rows: [
                ["日本語", "wide"],
                ["abc", "latin"],
            ],
        )

        let output = TableRenderer().render(table)

        #expect(output == """
        ┌────────┬─────────────┐
        │ name   │ description │
        ├────────┼─────────────┤
        │ 日本語 │ wide        │
        │ abc    │ latin       │
        └────────┴─────────────┘
        """)
    }

    @Test("draws borders around a headerless table without a header separator row")
    func rendersTableWithoutHeaders() {
        let table = Table(headers: [], rows: [["a", "1"], ["bb", "22"]])

        let output = TableRenderer().render(table)

        #expect(output == """
        ┌────┬────┐
        │ a  │ 1  │
        │ bb │ 22 │
        └────┴────┘
        """)
    }

    @Test("pads a short row's missing trailing cells as blank columns")
    func rendersRowShorterThanHeader() {
        let table = Table(headers: ["name", "description"], rows: [["solo"]])

        let output = TableRenderer().render(table)

        #expect(output == """
        ┌──────┬─────────────┐
        │ name │ description │
        ├──────┼─────────────┤
        │ solo │             │
        └──────┴─────────────┘
        """)
    }

    @Test("the Table result builder supports literal rows, conditional rows, and rows generated from a for-loop, producing headers and rows in declaration order")
    func buildsTableWithResultBuilder() {
        let includeLatin = true
        let extraRows = [
            ("emoji", "👨‍👩‍👧‍👦"),
            ("count", "3"),
        ]

        let table = Table {
            TableHeader {
                "name"
                "description"
            }
            TableRow {
                "日本語"
                "wide"
            }
            if includeLatin {
                TableRow("abc", "latin")
            }
            for row in extraRows {
                TableRow(row.0, row.1)
            }
        }

        #expect(table.headers == ["name", "description"])
        #expect(table.rows == [
            ["日本語", "wide"],
            ["abc", "latin"],
            ["emoji", "👨‍👩‍👧‍👦"],
            ["count", "3"],
        ])
    }

    @Test("a table constructed via the result builder renders with columns aligned by display width, matching the manually constructed table's output")
    func resultBuilderTablesRenderWithDisplayWidth() {
        let table = Table {
            TableHeader("name", "description")
            TableRow("日本語", "wide")
            TableRow("abc", "latin")
        }

        let output = TableRenderer().render(table)

        #expect(output == TableRenderer().render(Table(
            headers: ["name", "description"],
            rows: [["日本語", "wide"], ["abc", "latin"]],
        )))
    }
}
