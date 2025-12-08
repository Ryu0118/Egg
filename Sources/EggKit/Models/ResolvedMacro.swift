import Path

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
        case choice(String)
        case array([String])
        case path(AbsolutePath)
    }
}
