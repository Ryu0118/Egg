/// Evaluates JavaScript format expressions for array macro values.
protocol ArrayFormatEvaluating {
    /// Evaluates a format expression against array values.
    ///
    /// - Parameters:
    ///   - format: JavaScript expression referencing `$elements` for the array
    ///   - values: Array values to format
    /// - Returns: Formatted string result
    /// - Throws: `ArrayFormatError` on evaluation failure
    func evaluate(format: String?, values: [String]) throws -> String
}
