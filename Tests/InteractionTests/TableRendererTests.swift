@testable import Interaction
import Testing

@Suite("Builds and renders tables with column alignment based on terminal display width")
struct TableRendererTests {
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
