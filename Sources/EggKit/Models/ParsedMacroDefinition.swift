import Foundation

/// Represents a parsed macro definition from command line arguments.
///
/// The macro name is normalized to `___UPPER_SNAKE_CASE___` format.
/// For example, `--my-name` becomes `___MY_NAME___`.
package struct ParsedMacroDefinition: Equatable {
    /// The normalized macro name in `___UPPER_SNAKE_CASE___` format
    let macro: String

    /// The values associated with this macro
    let values: [String]
}
