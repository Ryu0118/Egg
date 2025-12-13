import Foundation

package struct ResolvedMacro: Equatable {
    package let name: String
    package let description: String
    package let value: Value

    package init(name: String, description: String, value: Value) {
        self.name = name
        self.description = description
        self.value = value
    }

    package enum Value: Equatable {
        case string(String)
        case boolean(Bool)
        /// Single selection from choices
        case choice(String)
        /// Multiple selection from choices
        case choices([String])
        /// Free-form array input with format expression
        case array([String], format: String?)
        case path(URL)
    }
}
