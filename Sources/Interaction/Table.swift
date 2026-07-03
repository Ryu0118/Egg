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
        var rows = table.rows
        if !table.headers.isEmpty {
            rows.insert(table.headers, at: 0)
        }

        let cellWidths = rows.map { $0.map(\.terminalDisplayWidth) }
        var columnWidths = [Int](repeating: 0, count: rows.map(\.count).max() ?? 0)
        for row in cellWidths {
            for (index, width) in row.enumerated() {
                columnWidths[index] = max(columnWidths[index], width)
            }
        }

        return zip(rows, cellWidths)
            .map { row, widths in render(row: row, cellWidths: widths, columnWidths: columnWidths) }
            .joined(separator: "\n")
    }

    private func render(row: [String], cellWidths: [Int], columnWidths: [Int]) -> String {
        columnWidths.indices.map { index in
            guard row.indices.contains(index) else { return "" }
            return row[index] + String(repeating: " ", count: columnWidths[index] - cellWidths[index])
        }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespaces)
    }
}
