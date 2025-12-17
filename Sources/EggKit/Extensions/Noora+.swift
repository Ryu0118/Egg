import Noora

extension Noorable {
    func passthrough(_ text: TerminalText, tab: UInt, indentSpace: UInt = 4) {
        let indent = String(repeating: " ", count: Int(tab * indentSpace))
        passthrough("\(indent)\(format(text))")
    }
}
