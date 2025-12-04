import Yams

extension YAMLEncoder {
    static func defaultEncoder() -> YAMLEncoder {
        let encoder = YAMLEncoder()
        encoder.options.newLineScalarStyle = .literal
        return encoder
    }
}
