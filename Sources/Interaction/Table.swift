/// A plain terminal table with headers and rows.
public struct Table: Equatable, Sendable {
    /// Column headers displayed before the rows.
    public let headers: [String]
    /// Row values displayed in table order.
    public let rows: [[String]]

    public init(headers: [String], rows: [[String]]) {
        self.headers = headers
        self.rows = rows
    }

    public init(@TableBuilder _ content: () -> [TableElement]) {
        var headers: [String] = []
        var rows: [[String]] = []

        for element in content() {
            switch element {
            case let .header(values):
                headers = values
            case let .row(values):
                rows.append(values)
            }
        }

        self.init(headers: headers, rows: rows)
    }
}

/// An element emitted by a table result builder.
public enum TableElement: Equatable, Sendable {
    case header([String])
    case row([String])
}

/// Header cells for a result-builder table declaration.
public struct TableHeader: Equatable, Sendable {
    /// Header cell values.
    public let values: [String]

    public init(_ values: String...) {
        self.values = values
    }

    public init(@TableCellBuilder _ content: () -> [String]) {
        values = content()
    }
}

/// Row cells for a result-builder table declaration.
public struct TableRow: Equatable, Sendable {
    /// Row cell values.
    public let values: [String]

    public init(_ values: String...) {
        self.values = values
    }

    public init(@TableCellBuilder _ content: () -> [String]) {
        values = content()
    }
}

/// Builds a table from header and row declarations.
@resultBuilder
public enum TableBuilder {
    public static func buildBlock(_ components: [TableElement]...) -> [TableElement] {
        components.flatMap(\.self)
    }

    public static func buildExpression(_ expression: TableHeader) -> [TableElement] {
        [.header(expression.values)]
    }

    public static func buildExpression(_ expression: TableRow) -> [TableElement] {
        [.row(expression.values)]
    }

    public static func buildOptional(_ component: [TableElement]?) -> [TableElement] {
        component ?? []
    }

    public static func buildEither(first component: [TableElement]) -> [TableElement] {
        component
    }

    public static func buildEither(second component: [TableElement]) -> [TableElement] {
        component
    }

    public static func buildArray(_ components: [[TableElement]]) -> [TableElement] {
        components.flatMap(\.self)
    }
}

/// Builds the cells inside a table header or row.
@resultBuilder
public enum TableCellBuilder {
    public static func buildBlock(_ components: [String]...) -> [String] {
        components.flatMap(\.self)
    }

    public static func buildExpression(_ expression: String) -> [String] {
        [expression]
    }

    public static func buildExpression(_ expression: StyledText) -> [String] {
        [expression.plainText]
    }

    public static func buildExpression(_ expression: some CustomStringConvertible) -> [String] {
        [expression.description]
    }

    public static func buildOptional(_ component: [String]?) -> [String] {
        component ?? []
    }

    public static func buildEither(first component: [String]) -> [String] {
        component
    }

    public static func buildEither(second component: [String]) -> [String] {
        component
    }

    public static func buildArray(_ components: [[String]]) -> [String] {
        components.flatMap(\.self)
    }
}

/// Renders tables as a bordered box using terminal display widths.
public struct TableRenderer: Sendable {
    public init() {}

    /// Returns a newline-separated, box-drawn terminal rendering of a table.
    public func render(_ table: Table) -> String {
        let columnWidths = columnWidths(for: table)
        guard !columnWidths.isEmpty else { return "" }

        var lines: [String] = [border(columnWidths, left: "┌", mid: "┬", right: "┐")]
        if !table.headers.isEmpty {
            lines.append(row(table.headers, columnWidths: columnWidths))
            lines.append(border(columnWidths, left: "├", mid: "┼", right: "┤"))
        }
        lines.append(contentsOf: table.rows.map { row($0, columnWidths: columnWidths) })
        lines.append(border(columnWidths, left: "└", mid: "┴", right: "┘"))

        return lines.joined(separator: "\n")
    }

    /// Widest cell (by terminal display width) in each column, across headers and rows.
    private func columnWidths(for table: Table) -> [Int] {
        var allRows = table.rows
        if !table.headers.isEmpty {
            allRows.insert(table.headers, at: 0)
        }
        guard let columnCount = allRows.map(\.count).max(), columnCount > 0 else { return [] }

        var widths = [Int](repeating: 0, count: columnCount)
        for row in allRows {
            for (index, cell) in row.enumerated() {
                widths[index] = max(widths[index], cell.terminalDisplayWidth)
            }
        }
        return widths
    }

    /// A horizontal border line, e.g. `┌────┬────┐`.
    private func border(_ columnWidths: [Int], left: String, mid: String, right: String) -> String {
        let segments = columnWidths.map { String(repeating: "─", count: $0 + 2) }
        return left + segments.joined(separator: mid) + right
    }

    /// A `│ cell │ cell │` line, padding each cell to its column's width.
    private func row(_ row: [String], columnWidths: [Int]) -> String {
        let cells = columnWidths.indices.map { index -> String in
            let value = row.indices.contains(index) ? row[index] : ""
            let padding = String(repeating: " ", count: columnWidths[index] - value.terminalDisplayWidth)
            return " " + value + padding + " "
        }
        return "│" + cells.joined(separator: "│") + "│"
    }
}
