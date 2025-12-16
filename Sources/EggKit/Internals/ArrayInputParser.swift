/// Normalizes array input from various sources.
struct ArrayInputParser {
    /// Parses CLI arguments (already split by MacrosParser).
    ///
    /// Each element may contain comma-separated values, which are flattened.
    func parseFromCLI(_ values: [String]) -> [String] {
        values
            .flatMap { splitByComma($0) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Parses interactive mode input (comma-separated string).
    func parseFromInteractive(_ input: String) -> [String] {
        splitByComma(input)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

private extension ArrayInputParser {
    func splitByComma(_ string: String) -> [String] {
        string.split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0) }
    }
}
