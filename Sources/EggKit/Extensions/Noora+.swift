import Noora

extension Noorable {
    func passthrough(_ text: TerminalText, tab: UInt, indentSpace: UInt = 4) {
        let indent = Array(repeating: " ", count: Int(tab * indentSpace)).joined()
        passthrough(TerminalText("\(indent)\(text.plain())"))
    }
}
