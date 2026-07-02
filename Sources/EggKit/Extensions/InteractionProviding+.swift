import Interaction

extension InteractionProviding {
    func writeLine(_ text: StyledText = "", tab: UInt = 0, indentSpace: UInt = 4) {
        let indent = String(repeating: " ", count: Int(tab * indentSpace))
        write("\(indent)\(text.plainText)\n")
    }

    func writeSuccess(_ message: StyledText) {
        writeStatus(.success, message)
    }

    func writeFailure(_ message: StyledText) {
        writeStatus(.failure, message)
    }

    func writeInfo(_ message: StyledText) {
        writeStatus(.info, message)
    }

    func writeWarning(_ message: StyledText) {
        writeStatus(.warning, message)
    }
}
