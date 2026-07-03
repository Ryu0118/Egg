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

/// Renders tables using terminal display widths.
public struct TableRenderer: Sendable {
    public init() {}

    /// Returns a newline-separated terminal rendering of a table.
    public func render(_ table: Table) -> String {
        let widths = columnWidths(for: table)
        var lines: [String] = []

        if !table.headers.isEmpty {
            lines.append(render(row: table.headers, widths: widths))
        }

        lines.append(contentsOf: table.rows.map { render(row: $0, widths: widths) })
        return lines.joined(separator: "\n")
    }

    private func columnWidths(for table: Table) -> [Int] {
        let columnCount = max(table.headers.count, table.rows.map(\.count).max() ?? 0)
        return (0 ..< columnCount).map { index in
            ([table.headers] + table.rows)
                .compactMap { row in row.indices.contains(index) ? row[index] : nil }
                .map(\.terminalDisplayWidth)
                .max() ?? 0
        }
    }

    private func render(row: [String], widths: [Int]) -> String {
        widths.indices.map { index in
            let value = row.indices.contains(index) ? row[index] : ""
            let padding = String(repeating: " ", count: widths[index] - value.terminalDisplayWidth)
            return value + padding
        }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespaces)
    }
}
