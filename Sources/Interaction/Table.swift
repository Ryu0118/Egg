public struct Table: Equatable, Sendable {
    public let headers: [String]
    public let rows: [[String]]

    public init(headers: [String], rows: [[String]]) {
        self.headers = headers
        self.rows = rows
    }
}

public struct TableRenderer: Sendable {
    public init() {}

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
