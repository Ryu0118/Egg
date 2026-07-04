@testable import Interaction
import Testing

struct TableRendererTests {
    @Test("renders tables using terminal display width")
    func rendersTablesUsingTerminalDisplayWidth() {
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

    @Test("builds table with result builder")
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

    @Test("result builder tables render with display width")
    func resultBuilderTablesRenderWithDisplayWidth() {
        let table = Table {
            TableHeader("name", "description")
            TableRow("日本語", "wide")
            TableRow("abc", "latin")
        }

        let output = TableRenderer().render(table)

        #expect(output.contains("name   description"))
        #expect(output.contains("日本語 wide"))
        #expect(output.contains("abc    latin"))
    }
}
